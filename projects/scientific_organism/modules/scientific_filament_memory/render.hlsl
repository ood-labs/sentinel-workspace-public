RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float3 current = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 memory = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float memoryLuma = luminance(memory);
    float filament = 1.0 - smoothstep(0.025, 0.11, abs(frac(memoryLuma * filament_bands) - 0.5));
    float3 echo = memory * echo_color + filament * memoryLuma * filament_color * filament_gain;
    float3 col = current + echo * memory_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
