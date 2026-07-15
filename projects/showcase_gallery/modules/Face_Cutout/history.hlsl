// face_cutout face_history — stores the current face (_Tex0 = Face_DS) into the ring head each
// frame. head = floor(_Time * capture_rate); older slots retain their frozen frames, forming a
// delay line the draw pass reads (interpolated) per clone.
#include "cutout_common.hlsli"

RWStructuredBuffer<float4> HistoryOut : register(u0);   // output: buffer:history (persistent)

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 p = DTid.xy;
    if (p.x >= HW || p.y >= HH) return;

    uint slot = ((uint)floor(_Time * capture_rate)) % HF;
    float2 uv = ((float2)p + 0.5) / float2((float)HW, (float)HH);
    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    HistoryOut[slot * HW * HH + p.y * HW + p.x] = float4(c, 1.0);
}
