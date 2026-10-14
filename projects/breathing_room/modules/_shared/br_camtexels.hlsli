// br_camtexels.hlsli -- SELF-DESCRIBING IMAGES: every image a pass hands on carries the camera it
// was rendered with, in a header row of texels, so a pass that combines images never has to ask
// which frame each one belongs to.
//
// Why (measured on this build, 0.6.3): a pass reading a buffer that ANOTHER pass of the same
// module writes is handed that buffer as it stood at the end of the previous cook -- one cook
// late per hop, for scratch and persistent buffers alike (BR_Render: shade read the G-buffer gbuf
// wrote a cook earlier, its scene frame counter and app clock exactly one ahead; every pass after
// prep read the scene a cook late). Only the camera cbuffer, _Time and external inputs are
// current. So a pass that rebuilt rays from the live camera and walked them through a G-buffer
// from the frame before lit every surface where it had been, and a TAA that took its "previous
// camera" from the scene buffer reprojected through a camera one frame older than its history:
// still, it all converged; moving, the lighting shimmered and the raw jittered frame flickered
// through everywhere. Now each image says which camera made it, and each pass that combines two
// images reprojects one into the other's camera.
//
// HEADER: texels (0..19, 0) of the image. Even texels of a pair hold the exact half-float part
// of a value, odd texels the remainder (~22 bits even in a 16-bit buffer):
//   0..7    view-projection rows 0..3       8, 9    eye (x, y, z, 1) -- the 1 is a validity tag
//   10..17  inverse view-projection rows    18      (jitter x, jitter y, frame mod 2048, 1)
//   19      reserved
// Readers never treat those texels as an image (isCamTexel / nearCamTexels).
#ifndef BR_CAMTEXELS_HLSLI
#define BR_CAMTEXELS_HLSLI

#define CAM_TEXELS 20
bool isCamTexel(int2 p) { return p.y == 0 && p.x < CAM_TEXELS; }
// a sample position (in texels) whose footprint could touch the header
bool nearCamTexels(float2 p) { return p.y < 3.0 && p.x < (float)CAM_TEXELS + 3.0; }

struct CamHdr
{
    float4x4 vp, ivp;
    float3 eye;
    float4 jit;          // jitter x, y (pixels), frame mod 2048, 1
    bool ok;
};

float4 camHalf(float4 v) { return f16tof32(f32tof16(v)); }
float4 camSplit(float4 v, int x) { float4 h = camHalf(v); return ((x & 1) == 0) ? h : v - h; }

// the value of header texel x
float4 camHeaderTexel(CamHdr c, int x)
{
    if (x >= 18) return (x == 18) ? c.jit : float4(0.0, 0.0, 0.0, 0.0);
    int r = x >> 1;
    float4 v;
    if (r == 0) v = c.vp[0];
    else if (r == 1) v = c.vp[1];
    else if (r == 2) v = c.vp[2];
    else if (r == 3) v = c.vp[3];
    else if (r == 4) v = float4(c.eye, 1.0);
    else if (r == 5) v = c.ivp[0];
    else if (r == 6) v = c.ivp[1];
    else if (r == 7) v = c.ivp[2];
    else v = c.ivp[3];
    return camSplit(v, x);
}

float4 camPair(Texture2D<float4> t, int x) { return t.Load(int3(x, 0, 0)) + t.Load(int3(x + 1, 0, 0)); }
// the camera an image carries; .ok is false when it carries none (a fresh or poisoned buffer)
CamHdr camHeader(Texture2D<float4> t)
{
    CamHdr c;
    float4 r0 = camPair(t, 0), r1 = camPair(t, 2), r2 = camPair(t, 4), r3 = camPair(t, 6), e = camPair(t, 8);
    float4 i0 = camPair(t, 10), i1 = camPair(t, 12), i2 = camPair(t, 14), i3 = camPair(t, 16);
    c.vp = float4x4(r0, r1, r2, r3);
    c.ivp = float4x4(i0, i1, i2, i3);
    c.eye = e.xyz;
    c.jit = t.Load(int3(18, 0, 0));
    // magnitude tests, never x == x (fast math folds a NaN self-compare to true)
    bool fin = all(abs(r0) < 1.0e4) && all(abs(r1) < 1.0e4) && all(abs(r2) < 1.0e4) && all(abs(r3) < 1.0e4) && all(abs(e) < 1.0e4)
            && all(abs(i0) < 1.0e6) && all(abs(i1) < 1.0e6) && all(abs(i2) < 1.0e6) && all(abs(i3) < 1.0e6);
    c.ok = fin && abs(e.w - 1.0) < 0.01 && dot(abs(r3), float4(1, 1, 1, 1)) > 1.0e-4 && abs(c.jit.w - 1.0) < 0.01;
    return c;
}
// the live camera, as a header (the pass where a camera enters the chain)
CamHdr camLive(float4x4 vp, float4x4 ivp, float3 eye, float2 jitter, float frame)
{
    CamHdr c;
    c.vp = vp; c.ivp = ivp; c.eye = eye;
    c.jit = float4(jitter, fmod(frame, 2048.0), 1.0);
    c.ok = true;
    return c;
}

// the eye ray through pixel `pix` (+ jitter) of a res-sized image rendered by camera c
void camRay(CamHdr c, float2 pix, float2 res, float2 jitter, out float3 ro, out float3 rd)
{
    float2 uv = (pix + 0.5 + jitter) / res;
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nw = mul(c.ivp, float4(ndc, 0.0, 1.0));
    float4 fw = mul(c.ivp, float4(ndc, 1.0, 1.0));
    nw /= nw.w; fw /= fw.w;
    ro = c.eye;
    rd = normalize(fw.xyz - nw.xyz);
}
// where world point w lands in camera c: uv (0..1, y down); false behind it or off screen
bool camProject(CamHdr c, float3 w, out float2 uv)
{
    float4 k = mul(c.vp, float4(w, 1.0));
    uv = float2(k.x / max(k.w, 1e-5) * 0.5 + 0.5, 0.5 - k.y / max(k.w, 1e-5) * 0.5);
    return k.w > 1e-3 && all(uv > 0.0) && all(uv < 1.0);
}
// how far the camera moved between two headers (sum of view-projection differences)
float camDelta(CamHdr a, CamHdr b)
{
    float s = 0.0;
    [unroll] for (int r = 0; r < 4; r++) { float4 d = a.vp[r] - b.vp[r]; s += abs(d.x) + abs(d.y) + abs(d.z) + abs(d.w); }
    return s;
}

#endif
