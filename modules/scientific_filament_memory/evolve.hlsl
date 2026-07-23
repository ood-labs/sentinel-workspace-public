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
    float2 texel = 1.0 / _Resolution.xy;
    float3 current = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float l = luminance(current);
    float gx = luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(texel.x, 0.0)), 0).rgb)
             - luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv - float2(texel.x, 0.0)), 0).rgb);
    float gy = luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0.0, texel.y)), 0).rgb)
             - luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv - float2(0.0, texel.y)), 0).rgb);
    float2 tangent = normalize(float2(-gy, gx) + float2(1e-5, 0.0));
    float2 historyUv = saturate(uv - tangent * drift_pixels * texel - drift_bias * texel);
    float3 previous = _Tex1.SampleLevel(LinearSampler, historyUv, 0).rgb;

    float dtScale = min(_DeltaTime, 0.05) * 60.0;
    float decay = pow(saturate(persistence), dtScale);
    float injection = smoothstep(injection_floor, injection_ceiling, l) * injection_gain;
    float3 energized = current * injection;
    float3 next = max(previous * decay, energized);
    next = lerp(next, max(next, previous * decay + energized * 0.3), accumulation);
    OutputUAV[tid.xy] = float4(saturate(next), 1.0);
}
