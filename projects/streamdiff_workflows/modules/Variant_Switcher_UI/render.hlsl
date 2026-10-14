// Variant_Switcher_UI / render - the art: the live Mux program on its stage (switcher_view.hlsli),
// on the instrument ground. The program is the thing being switched, so it is shown unaltered.
// The header, the controls, the cycle reading, the stage frame and the footer are recorded by
// layout.hlsl and drawn over this by ui.hlsl.
#include "../_shared/ui/il_core.hlsli"
#include "switcher_view.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y)
        return;

    float2 res = _Resolution.xy;
    float2 p = float2(tid.xy) + 0.5;
    uint inputWidth = 1u;
    uint inputHeight = 1u;
    _Tex0.GetDimensions(inputWidth, inputHeight);
    float4 stage = swStage(res, float2(inputWidth, inputHeight));

    float3 color = IL_FIELD;
    if (ilIn(p, stage))
    {
        float2 stageUv = saturate((p - stage.xy) / max(stage.zw - stage.xy, 1e-5.xx));
        color = _Tex0.SampleLevel(LinearSampler, stageUv, 0.0).rgb;
    }
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
