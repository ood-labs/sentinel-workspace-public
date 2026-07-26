RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 center = float2(0.5, 0.5) + lens_core;
    float2 p = (uv - center) * float2(aspect, 1.0);
    float radius = length(p);
    float2 radial = p / max(radius, 1e-5);
    float2 tangent = float2(-radial.y, radial.x);
    float angle = atan2(p.y, p.x);

    float normalizedRing = (radius - ring_radius) / max(ring_falloff, 0.001);
    float ringField = exp(-normalizedRing * normalizedRing);
    float pulse = 0.72 + 0.28 * sin(_Time * 0.31 + radius * 17.0);
    float torsionWave = sin(_Time * 0.19 + angle * 4.0);

    float2 warped = p;
    warped += radial * lens_strength * ringField * pulse;
    warped += tangent * torsion * ringField * torsionWave;

    float2 warpedUv = center + warped / float2(aspect, 1.0);
    warpedUv = clamp(warpedUv, 0.0, 1.0);
    float3 color = _Tex0.SampleLevel(LinearSampler, warpedUv, 0).rgb;

    float rim = 1.0 - smoothstep(
        ring_falloff * 0.10,
        ring_falloff * 0.32,
        abs(radius - ring_radius));
    color += rim * rim_gain * float3(0.31, 0.32, 0.29);

    float redDominance = max(0.0, color.r - max(color.g, color.b));
    float redLimiter = smoothstep(0.15, 0.52, redDominance);
    color = lerp(color, float3(color.r, color.g * 0.72, color.b * 0.58), redLimiter * 0.34);

    float2 corePx = p * _Resolution.y;
    float coreMark =
        (1.0 - smoothstep(0.0, 0.75, abs(corePx.x))) * step(abs(corePx.y), 11.0) +
        (1.0 - smoothstep(0.0, 0.75, abs(corePx.y))) * step(abs(corePx.x), 11.0);
    color += saturate(coreMark) * float3(0.17, 0.17, 0.15);

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
