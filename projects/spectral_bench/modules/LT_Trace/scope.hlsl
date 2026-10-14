// LT_Trace / scope.hlsl — an honest look at what is actually in the buffer.
//
// Deliberately NOT the program image. No haze, no bloom, no glass bodies: one hairline per traced
// segment, coloured by its wavelength, dimmed by the power it is carrying, with the three branch
// families distinguishable and every broken event marked. If the fan looks wrong downstream, this
// is where you find out whether the physics or the picture is at fault.
//
// This pass is the scope's ART only. Its words, frame, legend and inspector are layout.hlsl's, and
// ui.hlsl places this image over the bench. It draws the bench at L.artScale pixels per bench unit
// into the top-left corner of its texture, a fixed pixel budget (trace_view.hlsli), so a large
// canvas costs no more than the node preview always did.
#include "../_shared/bench.hlsli"
#include "../_shared/optics.hlsli"
#include "../_shared/ui/il_core.hlsli"
#include "trace_view.hlsli"

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
    TvLayout L = tvLayout(_Resolution.xy);
    float sc = L.artScale;
    float3 col = IL_WELL;

    // Outside the art's corner nothing is sampled: a two-pixel margin is cleared (the image's
    // filtering reaches half a texel past its edge), and the rest of the texture is left alone.
    if (P.x > L.art.x + 2.0 || P.y > L.art.y + 2.0) return;
    if (P.x > L.art.x || P.y > L.art.y) { OutputUAV[px] = float4(col, 1.0); return; }

    PathSeg H = Paths[LT_PATH_HDR];
    uint liveSegs = (uint)clamp(H.a.x, 0.0, (float)LT_PATH_TOTAL);
    uint stride   = (uint)clamp(H.depth, 1.0, (float)LT_MAX_SEG);
    uint nLane    = (uint)clamp(H.a.y, 0.0, (float)(LT_MAX_RAY * LT_MAX_WAVE * LT_BRANCH));

    // DECIMATE. A preview that walks every lane costs the same as the renderer and buys nothing:
    // 320 lanes is more than enough to see the shape of the transport, and the step is reported
    // rather than hidden (the header's LANES and DRAWN), because a silently sampled diagnostic is
    // worse than no diagnostic.
    uint step = tvStep(nLane);

    float3 acc = 0.0.xxx;
    [loop] for (uint li = 0u; li < nLane; li += step)
    {
        [loop] for (uint sj = 0u; sj < stride; ++sj)
        {
            uint slot = li * stride + sj;
            if (slot >= liveSegs) break;
            PathSeg g = Paths[slot];
            if (!ltSegLive(g)) break;

            float2 a = g.a * sc;
            float2 b = g.b * sc;
            float2 lo = min(a, b) - 2.5, hi = max(a, b) + 2.5;
            if (P.x < lo.x || P.x > hi.x || P.y < lo.y || P.y > hi.y) continue;

            float d = sdSeg(P, a, b);
            float w = saturate(1.6 - d);
            if (w <= 0.0) continue;

            float3 c = tvSegColour(g.wl, (int)g.evtEnd);
            acc += c * w * saturate(g.power) * (float)step * 0.55;
        }
    }

    col += acc;
    col = col / (1.0 + col);          // a plain reinhard: this is a scope, not a photograph
    OutputUAV[px] = float4(col, 1.0);
}
