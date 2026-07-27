RWTexture2D<float4> OutputUAV : register(u0);

float vector_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float vector_segment_distance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-7));
    return length(p - (a + ab * t));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float3 registered = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float4 trailState = _Tex1.SampleLevel(LinearSampler, uv, 0);

    float lum = vector_luma(registered);
    float3 neutral = lum * float3(0.96, 0.98, 0.94);

    float trailSignal = saturate(trailState.r * trail_gain);
    float freshSignal = saturate(trailState.g * trail_gain);
    float trail = smoothstep(trail_floor, min(1.0, trail_floor + 0.30), trailSignal);
    float fresh = smoothstep(trail_floor + 0.04, min(1.0, trail_floor + 0.34), freshSignal);
    float3 warmTrail = lerp(
        float3(0.42, 0.012, 0.003),
        float3(1.0, 0.115, 0.018),
        fresh * 0.48);
    float3 color = lerp(neutral, warmTrail, trail * 0.60);

    float2 p = (uv - float2(0.5, 0.5) - tracer_core) * float2(aspect, 1.0);
    float2 direction = normalize(float2(azimuth_x, azimuth_y) + float2(1e-5, 0.0));
    float needleDistance = vector_segment_distance(p, direction * 0.055, direction * 0.27);
    float needle = 1.0 - smoothstep(1.15 / _Resolution.y, 2.55 / _Resolution.y, needleDistance);
    needle *= smoothstep(0.08, 0.45, azimuth_confidence) * needle_restore;
    color = lerp(color, float3(1.0, 0.105, 0.018), needle);

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
