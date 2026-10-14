// The simulated haze (SS_Haze's Haze Field, ../_shared/ss_haze.hlsli) as the light passes read it. Density is in
// Haze units: 1 is the even haze the Haze control describes, so with no field linked, or Simulated Haze at 0, every
// lookup returns 1 and the picture is the even haze it always was. Define HF_TEX (the field's input) first, then
// call hzBegin once per thread.
#ifndef SS_HAZE_FIELD_HLSLI
#define SS_HAZE_FIELD_HLSLI
#include "../_shared/ss_haze.hlsli"

static HzDomain gHz;
static bool gHzOn;
static float gHzBase;
void hzBegin(HzDomain d)
{
    uint W, H;
    HF_TEX.GetDimensions(W, H);
    float4 hdr = (W == HF_W && H == HF_H) ? HF_TEX.Load(int3(0, HF_HDR_Y, 0)) : 0;
    gHz = d;
    gHzOn = hdr.y > 0.5 && haze_sim > 0.001;
    gHzBase = hdr.z;
}
// the simulated haze at p, as stored (Clear Air outside the grid)
float hzRaw(float3 p)
{
    float3 g = (p - gHz.lo) / (0.5 * gHz.h) - 0.5;
    if (any(g < -0.5) || any(g > float3(HZ_FX, HZ_FY, HZ_FZ) - 0.5)) return gHzBase;
    return atlasSample(HF_TEX, LinearSampler, g, HZ_FX, HZ_FY, HZ_FZ, HF_DEN_Y).r;
}
// the haze at p, relative to the Haze control
float hzDen(float3 p) { return gHzOn ? lerp(1.0, hzRaw(p), haze_sim) : 1.0; }
float3 hzVel(float3 p) { return atlasSample(HF_TEX, LinearSampler, (p - gHz.lo) / gHz.h - 0.5, HZ_AX, HZ_AY, HZ_AZ, HF_AIR_Y).xyz; }

// The structure finer than the 1/8 m haze grid, where the beams cut it (his hzShapeV): domain-warped noise eroding
// the density, its coordinates carried by the simulated air (a two-phase flow map: two copies of the noise each
// advected for one period then reset, crossfaded so neither reset shows), so the wisps travel and stretch with the
// cloud they belong to. Thin haze breaks into lumpy wisps; a cloud keeps a solid body and its edges fray. Haze Wisps
// sets how much, Wisp Size the scale. A short cycle and a capped carried speed: a long one drags the noise further
// than a wisp is wide in the fans' and the jets' fast air and smears it into streaks.
float hzDenWisps(float3 p)
{
    if (!gHzOn) return 1.0;
    float d = hzRaw(p);
    if (haze_wisps > 0.001)
    {
        float sc = 8.0 / max(wisp_size, 0.2);                   // noise texels per metre
        const float P = 1.0;
        float3 vel = hzVel(p);
        float vl = length(vel);
        float3 vc = vel * (vl > 0.35 ? 0.35 / vl : 1.0);
        float ph0 = frac(_Time / P), ph1 = frac(_Time / P + 0.5);
        float w0 = 1.0 - abs(2.0 * ph0 - 1.0);                  // each copy fades out as it resets
        float3 q0 = float3(p.x * 0.75, p.y, p.z) * sc;
        float n = 0.0;
        [unroll] for (uint k = 0; k < 2u; k++)
        {
            float ph = k == 0u ? ph0 : ph1;
            float3 q = q0 - float3(vc.x * 0.75, vc.y, vc.z) * sc * ph * P + (float)k * 23.7;
            float nk = hfNoise(HF_TEX, LinearSampler, q) * 0.64 + hfNoise(HF_TEX, LinearSampler, q * 2.37 + 31.7) * 0.36;
            n += nk * (k == 0u ? w0 : 1.0 - w0);
        }
        float m = saturate((d - gHzBase) / 2.0);                // how much of a cloud this is
        float thin = saturate(n * 1.6 - 0.15) * 1.25;            // lumpy wisps in the thin haze
        float body = smoothstep(0.12, 0.78, n + m * 0.45) * 1.1; // a solid core, edges fraying softly
        d *= lerp(1.0, lerp(thin, body, m), haze_wisps);
    }
    return lerp(1.0, d, haze_sim);
}
#endif
