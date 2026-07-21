// lfo display — node preview: a horizontal bar filling to the current 0..1 value.
StructuredBuffer<float4> Ctrl : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float v = Ctrl[0].y;
    float3 col = (uv.x < v) ? float3(0.2, 0.9, 0.5) : float3(0.08, 0.08, 0.11);
    OutputUAV[px] = float4(col, 1.0);
}
