// Public video output. The raymarch pass stores the laser classification mask
// in alpha, so this presentation pass restores the normal opaque video contract.

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)DTid.xy + 0.5) / _Resolution.xy;
    float3 color = _Tex0.SampleLevel(PointSampler, uv, 0).rgb;
    OutputUAV[DTid.xy] = float4(color, 1.0);
}
