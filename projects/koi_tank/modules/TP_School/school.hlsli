// TP_School / school.hlsli — declarations shared by this module's three passes.
#ifndef TP_SCHOOL_HLSLI
#define TP_SCHOOL_HLSLI

#include "../_shared/fish.hlsli"

// Ring length per fish for the preview's own trail history.
#define TP_TRAIL 64u

struct TpSCtl
{
    float4 a;   // (init, time, dtEff, cooks)
    float4 b;   // (trailHead, writeAccum, meanSpeed, spare)
};

// The envelope the school is allowed to occupy, derived from the tank and the envelope
// parameters. One function so the swim pass and the preview cannot disagree about where the
// boundary is — a preview that draws a different box from the one the fish are steering off is
// worse than no preview at all.
void tpSchoolBounds(TpRec tank, float margin, float dBias, float dBand,
                    out float3 lo, out float3 hi)
{
    float3 half3 = tpTankHalf(tank);              // (hx, depth, hz)
    float2 m = half3.xz * saturate(margin);

    // y runs from the floor at -depth up to the still waterline at 0. The band is centred on
    // depth_bias (0 = just under the surface, 1 = just off the floor) and never touches either.
    float yTop = -half3.y * 0.06;
    float yBot = -half3.y * 0.94;
    float yMid = lerp(yTop, yBot, saturate(dBias));
    float yHalf = (yTop - yBot) * 0.5 * saturate(dBand);

    lo = float3(-half3.x + m.x, max(yMid - yHalf, yBot), -half3.z + m.y);
    hi = float3( half3.x - m.x, min(yMid + yHalf, yTop),  half3.z - m.y);

    // A degenerate envelope would divide by zero downstream; keep it a real box.
    hi = max(hi, lo + 1e-3);
}

#endif // TP_SCHOOL_HLSLI
