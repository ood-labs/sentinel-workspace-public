// BR_Render / fogtaa.hlsl -- the beams, accumulated over time at their own quarter resolution.
//
// One frame of the beam march is noisy by design: its start is jittered (fog.hlsl) so that the
// average over frames is the true integral. The main TAA could not do that averaging once the
// camera moved. A quarter-resolution texel covers 4x4 full pixels, so the full-resolution 3x3
// neighbourhood the main TAA clips against sees the beam noise as one flat value, not as
// variance: it clamped history to each frame's noisy haze, and flying through the room the whole
// haze flickered like the lighting changing. Here a 3x3 neighbourhood IS nine independent noise
// samples, so the clip rejects only history that is really stale and keeps the converged beam.
//
// Both inputs reach this pass a cook late and each carries the camera that rendered it
// (br_camtexels.hlsli); every texel also carries the length its ray integrated (fogPack). A beam
// texel's world point is its own ray at that length, reprojected through the HISTORY's camera --
// never the live camera, which belongs to a later frame than either. Writes foghist (its own
// history, which the resolve reads) with the beam image's camera.
#include "render_common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// a texel of a beam buffer: in-scatter rgb, transmittance, ray length (header texels read as the
// row below)
struct FogS { float3 s; float T; float d; };
FogS fogLoad(Texture2D<float4> t, int2 p, int2 mx)
{
    p = clamp(p, int2(0, 0), mx);
    if (isCamTexel(p)) p.y = 1;
    float4 v = t.Load(int3(p, 0));
    float2 u = fogUnpack(v.a);
    FogS f;
    f.s = v.rgb; f.T = u.x; f.d = u.y;
    return f;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    int2 p = int2(tid.xy);
    int2 maxQ = int2(W - 1, H - 1);
    float4 fr = scFrame();
    CamHdr fc = camHeader(_Tex1);                 // the camera of the beam image
    if (!fc.ok) fc = camLive(_ViewProjMatrix, _InvViewProjMatrix, _CameraPos, fr.yz, fr.x);
    if (isCamTexel(p)) { OutputUAV[tid.xy] = camHeaderTexel(fc, p.x); return; }

    FogS cur = fogLoad(_Tex1, p, maxQ);
    float4 mn = 1e9, mx = -1e9, m1 = 0, m2 = 0;
    [unroll] for (int j = -1; j <= 1; j++)
    [unroll] for (int i = -1; i <= 1; i++)
    {
        FogS n = fogLoad(_Tex1, p + int2(i, j), maxQ);
        float4 c = float4(n.s, n.T);
        mn = min(mn, c); mx = max(mx, c);
        m1 += c; m2 += c * c;
    }
    m1 /= 9.0; m2 /= 9.0;
    float4 sd = sqrt(max(m2 - m1 * m1, 0.0));
    float4 bmin = max(mn, m1 - sd * 1.25), bmax = min(mx, m1 + sd * 1.25);

    // this texel's ray (fog.hlsl casts it through the centre of its 4x4 block) at the length it
    // integrated: where it ended -- the surface, or the room box through a window
    float2 fres = (_Resolution.x > 0.5) ? _Resolution : float2(W, H) * 4.0;
    float2 fullPix = (float2(p) + 0.5) * (fres / float2(W, H)) - 0.5;
    float3 ro, rd;
    camRay(fc, fullPix, fres, float2(0, 0), ro, rd);
    float3 wp = ro + rd * max(cur.d, 0.02);
    CamHdr hc = camHeader(_Tex3);                 // the camera of the history
    float2 puv;
    bool onScreen = hc.ok && camProject(hc, wp, puv);
    // never read history from the header texels: beside them, read just below
    if (nearCamTexels(puv * float2(W, H))) puv.y = max(puv.y, 3.5 / (float)H);

    float4 o = float4(cur.s, cur.T);
    if (taa != 0 && reset_accum == 0 && onScreen && fr.x > 2.0)
    {
        // bilinear by hand: alpha is packed, so each texel is unpacked before blending
        float2 tp = puv * float2(W, H) - 0.5;
        int2 i0 = (int2)floor(tp);
        float2 f = tp - (float2)i0;
        FogS a = fogLoad(_Tex3, i0, maxQ), b = fogLoad(_Tex3, i0 + int2(1, 0), maxQ);
        FogS c = fogLoad(_Tex3, i0 + int2(0, 1), maxQ), d = fogLoad(_Tex3, i0 + int2(1, 1), maxQ);
        float4 h = lerp(lerp(float4(a.s, a.T), float4(b.s, b.T), f.x), lerp(float4(c.s, c.T), float4(d.s, d.T), f.x), f.y);
        // a persistent buffer arrives uninitialised: magnitude tests, never x == x
        bool ok = abs(h.r) < 6e4 && abs(h.g) < 6e4 && abs(h.b) < 6e4 && h.a > -0.001 && h.a < 1.001;
        if (ok)
        {
            h = clamp(h, bmin, bmax);
            // still means the two images share a camera; the scene's still-count arrives late
            float staticF = (camDelta(fc, hc) > 1e-6) ? 0.0 : fr.w;
            // ~8 frames of history in motion; a still camera converges toward 1/20
            float alpha = (staticF > 1.0) ? max(1.0 / (staticF + 1.0), 0.05) : 0.12;
            o = lerp(h, o, alpha);
        }
    }
    bool good = abs(o.r) < 6e4 && abs(o.g) < 6e4 && abs(o.b) < 6e4 && abs(o.a) < 4.0;
    OutputUAV[tid.xy] = good ? float4(max(o.rgb, 0.0), fogPack(saturate(o.a), cur.d)) : float4(0, 0, 0, fogPack(1.0, cur.d));
}
