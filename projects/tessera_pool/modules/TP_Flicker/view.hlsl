// TP_Flicker / view.hlsl — where it is flashing, and how much.
//
// FIXED SCALE, always. This instrument exists to judge whether something has stopped moving, and
// an auto-ranging display cannot answer that question: as the signal decays its gain rises to
// match, so the picture looks identical at every amplitude and no change ever appears to help.
// That failure is the whole reason this module exists, so it is not going to repeat it here.
#include "../_shared/plan_theme.hlsli"
#include "../_shared/microfont.hlsli"

StructuredBuffer<float4> Hist : register(t0);
StructuredBuffer<float4> Metrics : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float aa(float d) { return saturate(0.5 - d); }
void ink(inout float3 dst, float3 col, float cov) { dst = lerp(dst, col, saturate(cov)); }

float2 cellSpace(float2 px, float2 org, float h, uint cells)
{
    return (px - org) / float2(h * 0.62 * (float)cells, h);
}
float drawStr(float2 px, float2 org, float h, uint2 p, uint n) { return mf_text(cellSpace(px, org, h, n), p, n); }
float strW(float h, uint cells) { return h * 0.62 * (float)cells; }

// fixed-point readout: id integer digits, a dot, dd decimals
float drawFix(float2 px, float2 org, float hgt, float value, uint id, uint dd)
{
    uint cells = id + 1u + dd;
    float2 p = cellSpace(px, org, hgt, cells);
    if (p.y < 0.0 || p.y >= 1.0) return 0.0;
    float fx = p.x * (float)cells;
    if (fx < 0.0 || fx >= (float)cells) return 0.0;
    uint i = (uint)fx;
    float2 lp = float2(frac(fx) * 1.2, p.y);
    if (i == id) return mf_glyph(lp, MF_DOT);
    uint sc = 1u; for (uint k = 0u; k < dd; k++) sc *= 10u;
    uint tot = (uint)round(clamp(value, 0.0, 999.0) * (float)sc);
    uint place = (i < id) ? ((id - 1u - i) + dd) : (dd - 1u - (i - id - 1u));
    uint div = 1u; for (uint m = 0u; m < place; m++) div *= 10u;
    return mf_glyph(lp, (tot / div) % 10u);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    float2 res = float2(W, H);
    float2 px = float2(tid.xy) + 0.5;

    uint sw = (uint)src_width, sh = (uint)src_height;
    uint2 sp = uint2(saturate(px / res) * float2(sw, sh));
    sp = min(sp, uint2(sw - 1u, sh - 1u));
    float4 h = Hist[sp.y * sw + sp.x];

    float hold = (abs(h.y) < 1e5) ? h.y : 0.0;

    // Fixed full scale. `view_scale` is in luminance units of the source image.
    float t = saturate(hold / max(view_scale, 1e-5));

    float3 c = PT_FIELD;
    c = lerp(c, PT_MID, saturate(t * 2.5));
    c = lerp(c, PT_ACCENT, saturate((t - 0.30) * 1.6));
    c = lerp(c, PT_ALARM, saturate((t - 0.70) * 3.5));

    // ---- readouts
    float mean = Metrics[0].x, peak = Metrics[0].y, area = Metrics[0].z;
    float gh = max(res.y * 0.026, 8.0);
    float2 o = float2(res.x * 0.035, res.y * 0.035);

    ink(c, PT_INK, drawStr(px, o, gh, uint2(mf_pack1(15u,21u,18u,12u,20u), mf_pack1(14u,27u,0u,0u,0u)), 7u));   // FLICKER

    float2 r1 = o + float2(0.0, gh * 2.0);
    ink(c, PT_DIM, drawStr(px, r1, gh, uint2(mf_pack1(22u,14u,10u,23u,0u), 0u), 4u));                            // MEAN
    ink(c, PT_MID, drawFix(px, r1 + float2(strW(gh, 5u), 0), gh, mean * 100.0, 2u, 3u));

    float2 r2 = r1 + float2(0.0, gh * 1.5);
    ink(c, PT_DIM, drawStr(px, r2, gh, uint2(mf_pack1(25u,14u,10u,20u,0u), 0u), 4u));                            // PEAK
    ink(c, PT_MID, drawFix(px, r2 + float2(strW(gh, 5u), 0), gh, peak * 100.0, 2u, 3u));

    // AREA is instantaneous: percent of the image visibly changing on this frame. The map
    // remains peak-held so a brief flash can still be located after it happens.
    float2 r3 = r2 + float2(0.0, gh * 1.5);
    bool bad = area > max(area_alarm, 1e-6);
    ink(c, PT_DIM, drawStr(px, r3, gh, uint2(mf_pack1(10u,27u,14u,10u,0u), 0u), 4u));                            // AREA
    ink(c, bad ? PT_ALARM : PT_MID, drawFix(px, r3 + float2(strW(gh, 5u), 0), gh, area * 100.0, 2u, 2u));

    if (bad)
    {
        float e = min(min(px.x, px.y), min(res.x - px.x, res.y - px.y));
        ink(c, PT_ALARM, (1.0 - smoothstep(0.0, 3.0, e)) * 0.85);
    }

    OutputUAV[tid.xy] = float4(c, 1.0);
}
