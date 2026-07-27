RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float2 rotate_local(float2 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5 - aperture_core) * float2(aspect, 1.0);
    float2 q = rotate_local(p, -0.22);

    float3 memoryColor = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 seedColor = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float difference = abs(luminance(memoryColor) - luminance(seedColor));

    float aperture = 0.0;
    float boundary = 0.0;
    if (aperture_mode == 0)
    {
        float radius = length(p);
        float angle = atan2(p.y, p.x);
        float lobeRadius = void_scale * (0.58 + 0.13 * sin(angle * 5.0 - _Time * 0.10));
        aperture = 1.0 - smoothstep(lobeRadius, lobeRadius + edge_softness, radius);
        boundary = 1.0 - smoothstep(edge_softness, edge_softness * 3.0, abs(radius - lobeRadius));
    }
    else if (aperture_mode == 1)
    {
        float diagonal = q.x * 0.70 + q.y * 0.44;
        float gap = void_scale * 0.34;
        aperture = smoothstep(gap, gap + edge_softness, abs(diagonal));
        float frame = max(abs(q.x) - 0.83, abs(q.y) - 0.50);
        aperture *= 1.0 - smoothstep(0.0, edge_softness * 2.0, frame);
        boundary =
            1.0 - smoothstep(edge_softness, edge_softness * 3.0, abs(abs(diagonal) - gap));
    }
    else
    {
        float2 cellUv = q / max(void_scale * 0.23, 0.035);
        float2 cell = floor(cellUv);
        float2 local = frac(cellUv) - 0.5;
        float selector = frac((cell.x * 0.6180339 + cell.y * 0.3819660) * 0.5);
        float plate = max(abs(local.x), abs(local.y));
        float active = step(0.38, selector);
        aperture = active * (1.0 - smoothstep(0.34, 0.44, plate));
        boundary = active * (1.0 - smoothstep(0.018, 0.055, abs(plate - 0.39)));
    }

    float diffMask = smoothstep(difference_gate, difference_gate + 0.16, difference);
    float outsideTrace = diffMask * (1.0 - aperture) * seed_reveal;
    float3 color = memoryColor * aperture * memory_gain;
    color = max(color, seedColor * outsideTrace);

    float visibleMask = saturate(aperture + outsideTrace);
    float redDominance = max(seedColor.r, memoryColor.r) - max(max(seedColor.g, seedColor.b), max(memoryColor.g, memoryColor.b));
    float accent = smoothstep(0.08, 0.34, redDominance) * visibleMask * accent_gain;
    color = lerp(color, float3(max(color.r, 0.72), color.g * 0.30, color.b * 0.10), accent);

    color += boundary * float3(0.23, 0.24, 0.22);

    float2 corePx = p * _Resolution.y;
    float coreMark =
        (1.0 - smoothstep(0.0, 0.85, abs(corePx.x))) * step(abs(corePx.y), 18.0) +
        (1.0 - smoothstep(0.0, 0.85, abs(corePx.y))) * step(abs(corePx.x), 18.0);
    color += saturate(coreMark) * float3(0.30, 0.30, 0.27);

    float edgeFade = smoothstep(0.0, 0.045, uv.x) * smoothstep(0.0, 0.045, uv.y);
    edgeFade *= smoothstep(0.0, 0.045, 1.0 - uv.x) * smoothstep(0.0, 0.045, 1.0 - uv.y);
    color *= edgeFade;

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
