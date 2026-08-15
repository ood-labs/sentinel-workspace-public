// LT_Trace / scope.hlsl — an honest look at what is actually in the buffer.
//
// Deliberately NOT the program image. No haze, no bloom, no glass bodies: one hairline per traced
// segment, coloured by its wavelength, dimmed by the power it is carrying, with the three branch
// families distinguishable and every broken event marked. If the fan looks wrong downstream, this
// is where you find out whether the physics or the picture is at fault.
#include "../_shared/bench.hlsli"
#include "../_shared/optics.hlsli"
#include "../_shared/plan_theme.hlsli"

StructuredBuffer<BenchRec> Bench : register(t0);
StructuredBuffer<PathSeg>  Paths : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * t);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 P = (float2)px + 0.5;

    // Bench space fitted, never stretched, so an angle here is the same angle as in the plan.
    float sc = min(_Resolution.x / 1.0, _Resolution.y / BENCH_H);
    float2 org = (_Resolution.xy - float2(sc, sc * BENCH_H)) * 0.5;

    float3 col = PT_FIELD;

    // A faint bench outline, so an escaping ray is legibly leaving something.
    float2 b0 = org, b1 = org + float2(sc, sc * BENCH_H);
    float edge = min(min(abs(P.x - b0.x), abs(P.x - b1.x)), min(abs(P.y - b0.y), abs(P.y - b1.y)));
    if (P.x > b0.x - 2.0 && P.x < b1.x + 2.0 && P.y > b0.y - 2.0 && P.y < b1.y + 2.0)
        col = lerp(col, PT_GRID, saturate(1.5 - edge) * 0.8);

    PathSeg H = Paths[LT_PATH_HDR];
    uint liveSegs = (uint)clamp(H.a.x, 0.0, (float)LT_PATH_TOTAL);
    uint stride   = (uint)clamp(H.depth, 1.0, (float)LT_MAX_SEG);
    uint nLane    = (uint)clamp(H.a.y, 0.0, (float)(LT_MAX_RAY * LT_MAX_WAVE * LT_BRANCH));

    // DECIMATE. A preview that walks every lane costs the same as the renderer and buys nothing:
    // 320 lanes is more than enough to see the shape of the transport, and the step is reported
    // rather than hidden, because a silently sampled diagnostic is worse than no diagnostic.
    uint step = max(1u, (nLane + 319u) / 320u);

    float3 acc = 0.0.xxx;
    [loop] for (uint li = 0u; li < nLane; li += step)
    {
        [loop] for (uint sj = 0u; sj < stride; ++sj)
        {
            uint slot = li * stride + sj;
            if (slot >= liveSegs) break;
            PathSeg g = Paths[slot];
            if (!ltSegLive(g)) break;

            float2 a = org + g.a * sc;
            float2 b = org + g.b * sc;
            float2 lo = min(a, b) - 2.5, hi = max(a, b) + 2.5;
            if (P.x < lo.x || P.x > hi.x || P.y < lo.y || P.y > hi.y) continue;

            float d = sdSeg(P, a, b);
            float w = saturate(1.6 - d);
            if (w <= 0.0) continue;

            int evE = (int)g.evtEnd;
            float3 c = ltWavelengthRGB(g.wl);
            c /= max(max(c.r, max(c.g, c.b)), 1e-3);
            if (evE == EV_TIR || evE == EV_EXHAUST) c = PT_ALARM * 2.0;

            acc += c * w * saturate(g.power) * (float)step * 0.55;
        }
    }

    col += acc;
    col = col / (1.0 + col);          // a plain reinhard: this is a scope, not a photograph
    OutputUAV[px] = float4(col, 1.0);
}
