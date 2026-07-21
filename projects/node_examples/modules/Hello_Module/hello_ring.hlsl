RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 dispatchId : SV_DispatchThreadID)
{
    uint2 pixel = dispatchId.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float radius = lerp(0.13, 0.38, pulse);
    float ring = 1.0 - smoothstep(0.012, 0.032, abs(length(p) - radius));
    float halo = exp(-18.0 * abs(length(p) - radius));
    float3 background = lerp(float3(0.015, 0.025, 0.07),
                             float3(0.08, 0.015, 0.11), uv.y);
    float3 ringColor = lerp(float3(0.15, 0.85, 1.0),
                            float3(1.0, 0.22, 0.65), pulse);
    float3 color = background + ringColor * (ring + 0.35 * halo);

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
