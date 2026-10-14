// BR_Lens / grade.hlsl -- the picture: the visual field, bloom, a camera white balance, exposure,
// the trip's colour (saturation that deepens with the dose, hues that drift slowly in broad
// regions), contrast, the filmic view, a gentle vignette, chromatic fringing toward the edges and
// film grain. Inputs: 0 BR_Render's HDR (radiance + depth, read directly), 1..4 the glow levels
// (1/2 .. 1/16, glow.hlsl), data 0 trip, data 1 scene.
//
// TIMING. This build hands a pass another pass's buffer a cook late, per hop, so the fewer hops
// between the renderer and this pass, the less the picture lags the camera. The image is read
// here directly: no hop. Every glow level is one hop from the same source: it arrives one cook
// late and carries the camera it was made with (texels (0..19, 0) of the half-resolution level,
// br_camtexels.hlsli), so each pixel finds its glow where that point sat in THAT camera. The old
// lens copied the image first and built the glow down and up a seven-pass pyramid: the picture ran
// a cook behind the renderer and every lamp's halo seven behind the picture. The Bloom Timing
// view shows the measured lag.
#include "lens_common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float lensHash(float2 p, float f) { return frac(sin(dot(p, float2(12.9898, 78.233)) + f * 0.61803) * 43758.5453); }

// a sample position kept off an image's header texels
float2 offHeader(float2 uv, float2 res) { return nearCamTexels(uv * res) ? float2(uv.x, max(uv.y, 3.5 / res.y)) : uv; }

// a 3x3 tent of bilinear taps one texel apart: smooth enough that a coarse level shows no grid
float3 glowTent(Texture2D<float4> t, float2 uv, bool header)
{
    uint w, h, lv;
    t.GetDimensions(0, w, h, lv);
    float2 res = float2(w, h);
    float2 d = 1.0 / res;
    float3 s = 0;
    [unroll] for (int j = -1; j <= 1; j++)
    [unroll] for (int i = -1; i <= 1; i++)
    {
        float2 q = uv + float2(i, j) * d;
        if (header) q = offHeader(q, res);
        s += t.SampleLevel(LinearSampler, q, 0).rgb * ((i == 0 ? 2.0 : 1.0) * (j == 0 ? 2.0 : 1.0));
    }
    return s / 16.0;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    float2 res = float2(W, H);
    float2 uv = (float2(tid.xy) + 0.5) / res;
    int2 mxP = int2(W - 1, H - 1);
    BRTrip T = tripHeader();
    float trip = T.dose;
    CamHdr fc = camHeader(_Tex0);              // the image, as rendered
    CamHdr gc = camHeader(_Tex1);              // the image the glow was made from, a cook earlier

    // the visual field: where this pixel reads the image (lens_common: lensWarp), the trip's
    // anchors projected through the image's own camera
    float4x4 vp = fc.ok ? fc.vp : lensViewProj();
    float2 suv = offHeader(saturate(uv + lensWarp(uv, res.x / res.y, T, vp, trip_warp)), res);
    // chromatic fringing grows toward the edges (and a little with the trip)
    float2 fromC = uv - 0.5;
    float ab = aberration * (0.0018 + 0.0022 * trip * T.colour * tripAmp(T)) * dot(fromC, fromC) * 4.0;
    float3 cur;
    cur.r = _Tex0.SampleLevel(LinearSampler, offHeader(suv - fromC * ab, res), 0).r;
    cur.g = _Tex0.SampleLevel(LinearSampler, suv, 0).g;
    cur.b = _Tex0.SampleLevel(LinearSampler, offHeader(suv + fromC * ab, res), 0).b;
    int2 p0 = clamp((int2)floor(suv * res), int2(0, 0), mxP);
    float4 f0 = _Tex0.Load(int3(p0, 0));

    // the glow (already exposed by glow.hlsl), where this point sat in the glow's camera
    float3 ro, rd;
    camRay(fc, suv * res - 0.5, res, float2(0, 0), ro, rd);
    float3 wp = ro + rd * min(max(abs(f0.a), 0.05), 400.0);
    float2 guv = suv;
    if (!(fc.ok && gc.ok && camProject(gc, wp, guv))) guv = suv;
    float3 bl = glowTent(_Tex1, guv, true) + glowTent(_Tex2, guv, false) + glowTent(_Tex3, guv, false) + glowTent(_Tex4, guv, false);
    float3 c = cur * exp2(exposure) + bl * bloom * 0.12;
    // white balance: neutralise the chosen colour temperature (the light is physical; this is the camera)
    c /= brKelvin(white_balance);
    // the lamps' rainbows, in the eye: evaluated where this pixel reads the image, so they ride the
    // visual field with the lamps they come off
    c += lensLampRainbows(suv, res.x / res.y, T, fc, _Tex0, res, lamp_rainbows) * exp2(exposure);
    // the trip's colour: saturation deepens with the dose, hues drift in broad slow regions.
    // Overdrive swings the hues much further, in smaller regions, and saturates harder.
    float colourK = T.colour * trip;
    float hueDrift = brVN3(float3(uv * float2(res.x / res.y, 1.0) * 1.3 * tripFreq(T), T.time * 0.035)) * colourK * 0.35 * tripAmp(T);
    c = max(lensHueRotate(c, hueDrift), 0.0);
    c = lensSaturate(c, saturation * (1.0 + colourK * 0.35 * (1.0 + 0.8 * T.push)));
    // contrast around middle grey, in log space
    float lum = max(brLuma(c), 1e-5);
    float lumC = exp2((log2(lum) - log2(0.18)) * contrast + log2(0.18));
    c *= lumC / lum;
    // the filmic view, vignette, grain
    float3 o = lensFilmic(c);
    float vig = 1.0 - vignette * smoothstep(0.25, 0.95, length(fromC * float2(res.x / res.y, 1.0)) * 1.1);
    o *= vig;
    o = brLinearToSrgb(o);
    float gr = (lensHash(float2(tid.xy), frac(T.time * 17.0 + _Time * 13.0)) - 0.5) * grain * 0.08;
    o += gr * (1.0 - o * 0.6);
    if (view == 1) o = saturate(abs(f0.a) * 0.1).xxx;
    else if (view >= 2) o = brLinearToSrgb(lensFilmic(bl * 0.12 / brKelvin(white_balance)));
    // BLOOM TIMING, top left: did the image and the glow each carry a readable camera (green) or
    // not (red), then one white block per renderer frame the glow's source lags the image
    if (view == 3 && tid.y >= 4 && tid.y < 18)
    {
        int lag = (int)round(fmod(fc.jit.z - gc.jit.z + 2048.0, 2048.0));
        int cell = (int)tid.x / 16;
        bool gap = ((int)tid.x % 16) >= 14;
        if (cell == 0 || cell == 1)
        {
            bool g = (cell == 0) ? fc.ok : gc.ok;
            o = gap ? float3(0, 0, 0) : (g ? float3(0.1, 0.8, 0.2) : float3(0.9, 0.1, 0.1));
        }
        else if (cell >= 2 && cell - 2 < min(lag, 30))
            o = gap ? float3(0, 0, 0) : float3(0.95, 0.95, 0.95);
    }
    OutputUAV[tid.xy] = float4(saturate(o), 1.0);
}
