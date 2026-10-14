// Timeline / stage - the picture at the playhead, drawn into the stage pane with the program's own
// shading (tlComposite in timeline.hlsli), for the layout pass to show as an image. The Sting draws
// the same picture, adding motion blur across its shutter.
//
// Each 16x16 group works the twenty channel values out once, into groupshared memory, before any
// pixel shades: evaluating them per pixel would cost twenty key searches a pixel.
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "tl.hlsli"

RWTexture2D<float4> StageUAV : register(u0);
groupshared float gsV[TL_CH];

[numthreads(16, 16, 1)]
void main(uint3 id : SV_DispatchThreadID, uint gi : SV_GroupIndex)
{
    uint W, H;
    StageUAV.GetDimensions(W, H);
    float2 res = float2(W, H);
    if (gi < TL_CH) gsV[gi] = tlValue(gi, tlPlayhead());
    GroupMemoryBarrierWithGroupSync();
    if (id.x >= W || id.y >= H) return;
    TlLayout L = tlLayout(res, ilCtx(res).s, S[TL_V4].xy);
    float2 p = float2(id.xy) + 0.5;
    if (!ilIn(p, ilInset(L.stage, -2.0))) return;          // only the stage is ever sampled
    float4 xf[TL_LAYERS];
    float op[TL_LAYERS];
    [unroll] for (uint l = 0u; l < TL_LAYERS; l++)
    {
        uint c = l * TL_ATTRS;
        xf[l] = float4(gsV[c], gsV[c + 1u], gsV[c + 2u], gsV[c + 3u]);
        op[l] = saturate(gsV[c + 4u]);
    }
    StageUAV[id.xy] = float4(tlComposite(tlPxToStage(L.stage, p), L.stage.w - L.stage.y, xf, op), 1.0);
}
