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
    float3 center = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float l = luminance(center);
    float left = luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv - float2(texel.x * sample_span, 0.0)), 0).rgb);
    float right = luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(texel.x * sample_span, 0.0)), 0).rgb);
    float up = luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv - float2(0.0, texel.y * sample_span)), 0).rgb);
    float down = luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0.0, texel.y * sample_span)), 0).rgb);
    float2 gradient = float2(right - left, down - up);
    float3 normal = normalize(float3(-gradient * relief_depth, normal_floor));
    float3 light = normalize(float3(light_direction, light_height));
    float diffuse = saturate(dot(normal, light));
    float rim = pow(saturate(1.0 - normal.z), rim_power);

    float terrace = floor(saturate(l) * terrace_count) / max(terrace_count - 1.0, 1.0);
    float terraceEdge = 1.0 - smoothstep(0.02, 0.12, abs(frac(l * terrace_count) - 0.5));
    float shadowSample = luminance(_Tex0.SampleLevel(
        LinearSampler,
        saturate(uv - normalize(light_direction + float2(1e-4, 0.0)) * texel * shadow_offset),
        0).rgb);
    float selfShadow = saturate((l - shadowSample) * shadow_gain + 0.5);

    float reliefTone = lerp(0.42, 1.22, diffuse) * lerp(0.72, 1.18, selfShadow);
    float3 sculpted = center * reliefTone;
    sculpted += terrace * terrace_color * terrace_mix;
    sculpted += terraceEdge * l * edge_color * edge_mix;
    sculpted += rim * rim_color * rim_mix;
    float amberMask = saturate(center.r - max(center.g, center.b) * 1.6);
    sculpted = lerp(sculpted, center + sculpted * 0.18, amberMask);
    OutputUAV[tid.xy] = float4(saturate(lerp(center, sculpted, relief_mix)), 1.0);
}
