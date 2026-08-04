// TP_Caustics / atlas.hlsl — the node's instrument view of the unfolded tank interior.
//
// The raw caustic output is an HDR multiplier and previews as a blown-out white mess. This view
// is the readable one: the value ladder carries brightness, the region frames say which surface
// you are looking at, and the accent marks the ONE contour that means anything on its own —
// irradiance exactly 1.0, the level a perfectly still surface would produce everywhere. Where
// the atlas sits on that line the water is flat; the distance from it is the whole content.
//
// Hue appears twice and both are earned: a muted identity colour on each of the four wall
// regions, because an unfolded box is genuinely ambiguous about which wall is which, and the
// reserved accent on the neutral contour.
#include "../_shared/tessera.hlsli"
#include "../_shared/plan_theme.hlsli"

StructuredBuffer<TpRec> Plan : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float aa(float d) { return saturate(0.5 - d); }
void ink(inout float3 dst, float3 col, float cov) { dst = lerp(dst, col, saturate(cov)); }

float frameCov(float2 px, float2 lo, float2 hi, float w)
{
    float2 c = (lo + hi) * 0.5, h = (hi - lo) * 0.5;
    float2 q = abs(px - c) - h;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    return aa(abs(d) - w * 0.5);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    float2 res = float2(W, H);
    float2 px = float2(tid.xy) + 0.5;
    float2 uv = px / res;

    TpRec tank = Plan[TP_TANK];
    float3 half3 = tpTankHalf(tank);

    float3 samp = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float e = samp.r;
    float wa, aa2;
    int region = tpAtlasRegion(uv, half3, wa, aa2);

    float3 c = PT_FIELD;

    // RAW COUNTS is a shipped view, not scaffolding. In a node whose whole behaviour is
    // invisible bookkeeping — a scatter into a buffer nobody can see — it is the only way to
    // tell "no photons arrived" from "photons arrived and the normalisation ate them", and
    // those two have identical symptoms and completely different fixes.
    if ((int)view_mode >= 1)
    {
        float raw = ((int)view_mode == 2) ? samp.b : samp.g;
        float t2 = saturate(raw / max(count_scale, 0.01));
        c = lerp(PT_WELL, PT_INK, t2);
        ink(c, PT_ALARM, (raw > 0.0 && t2 < 0.02) ? 0.35 : 0.0);
        OutputUAV[tid.xy] = float4(c, 1.0);
        return;
    }

    if (region >= 0)
    {
        // value ladder: 0 at the well, 1.0 (flat water) at mid, brighter above
        float t = saturate(e * 0.62);
        c = lerp(PT_WELL, PT_MID, t);
        c = lerp(c, PT_INK, saturate((e - 1.6) * 0.35));

        // The neutral contour, e == 1. A fixed tolerance rather than a screen-derivative width:
        // no derivatives in a compute shader, and a caustic's gradient swings over orders of
        // magnitude between a cusp and a dead zone, so a slope-derived width would draw a
        // hairline in one place and a slab in another.
        ink(c, PT_ACCENT, (1.0 - smoothstep(0.0, 0.012, abs(e - 1.0))) * 0.65);
    }

    // region frames, with a muted identity colour per wall
    float2 c0 = float2(TP_A_C0, TP_A_C0) * res, c1 = float2(TP_A_C1, TP_A_C1) * res;
    ink(c, PT_DIM, frameCov(px, c0, c1, 1.4));
    ink(c, ptId(0), frameCov(px, float2(TP_A_LO, TP_A_C0) * res, float2(TP_A_C0, TP_A_C1) * res, 1.2));
    ink(c, ptId(1), frameCov(px, float2(TP_A_C1, TP_A_C0) * res, float2(TP_A_HI, TP_A_C1) * res, 1.2));
    ink(c, ptId(2), frameCov(px, float2(TP_A_C0, TP_A_LO) * res, float2(TP_A_C1, TP_A_C0) * res, 1.2));
    ink(c, ptId(3), frameCov(px, float2(TP_A_C0, TP_A_C1) * res, float2(TP_A_C1, TP_A_HI) * res, 1.2));

    OutputUAV[tid.xy] = float4(c, 1.0);
}
