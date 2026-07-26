// CRYOGRAM / SPECIMEN — structure tap for the measurement branch.
//
// The same solidification state, read for a detector instead of for an eye.
// No hatching, no twinning, no liquid grain: those are surface texture and they
// alias into a moire storm at analysis resolution.
//
// Grains are drawn BRIGHT and separated by a DARK gap along every grain
// boundary. That separation is what lets a luma-threshold connected-component
// pass resolve one blob per grain instead of fusing the whole plate into a
// single component, and it leaves the facet outlines as clean corner and line
// content.

RWTexture2D<float4> OutputUAV : register(u0);

#include "shock.hlsli"
StructuredBuffer<Shock> Shocks : register(t1);
#include "shock_apply.hlsli"

float4 loadState(int2 p, uint2 res) {
    return _Tex0.Load(int3(clamp(p, int2(0, 0), int2(res) - 1), 0));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    // NOT displaced. The shock is a presentation effect; feeding it to the
    // detector made every corner lurch on each snare, so no track could stay
    // confirmed long enough to bond and the whole measurement layer collapsed
    // to zero. The instrument measures the material, which has not moved —
    // survey markers stay put while the plate visibly shudders under them.
    int2 px = int2(id.xy);

    float4 st = loadState(px, res);
    float s = st.r, gid = st.b, age = st.a;
    bool solid = s >= 0.999;
    bool resorbing = (gid > 0.0) && (age > anneal_life);

    if (!solid || resorbing || gid <= 0.0) {
        OutputUAV[id.xy] = float4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Dark separator: any different grain, or any non-solid cell, within the gap
    // radius knocks this cell out. Gap is authored in source pixels so it
    // survives the downsample into the analysis branch.
    int gap = max((int)round(structure_gap), 1);
    for (int dy = -gap; dy <= gap; ++dy) {
        for (int dx = -gap; dx <= gap; ++dx) {
            if (dx * dx + dy * dy > gap * gap) continue;
            float4 n = loadState(px + int2(dx, dy), res);
            bool nsolid = n.r >= 0.999;
            bool nres = (n.b > 0.0) && (n.a > anneal_life);
            if (!nsolid || nres || n.b <= 0.0 || abs(n.b - gid) > 0.004) {
                OutputUAV[id.xy] = float4(0.0, 0.0, 0.0, 1.0);
                return;
            }
        }
    }

    // BINARY. Per-grain gray levels here made the detector's luma threshold do
    // two jobs at once (select material AND select which grains), so component
    // separation depended on gray collisions instead of on the gap. Grain
    // identity is the tracker's job, not the threshold's.
    OutputUAV[id.xy] = float4(1.0, 1.0, 1.0, 1.0);
}
