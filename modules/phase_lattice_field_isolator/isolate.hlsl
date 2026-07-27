RWTexture2D<float4> OutputUAV : register(u0);

float isolator_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float lum = isolator_luma(source);

    float2 p = (uv - float2(0.5, 0.5) - isolator_core) * float2(aspect, 1.0);
    float radius = length(p);

    float specimen = 1.0 - smoothstep(
        specimen_radius - transition_width,
        specimen_radius + transition_width,
        radius);

    float ringDistance = abs(radius - measure_radius);
    float registrationBand = 1.0 - smoothstep(
        registration_width * 0.35,
        registration_width,
        ringDistance);

    // A narrow, source-derived registration band remains visible while
    // unrelated outer contours recede into the black field.
    float structureGain = max(
        lerp(outer_gain, 1.0, specimen),
        registrationBand * registration_restore);

    float3 neutral = lum * float3(0.96, 0.98, 0.94);
    float warmDominance = saturate(source.r - max(source.g, source.b));
    float keepWarm = specimen * smoothstep(0.01, 0.12, warmDominance);
    float3 disciplined = lerp(neutral, source, keepWarm);

    // Keep the nucleus and immediate lobe roots untouched; only the
    // exterior field is dimmed.
    float3 color = disciplined * structureGain;
    color = lerp(color, source, specimen);

    // The outer field keeps only source-derived high-energy contour ridges.
    // This removes the low-level moire fog without imposing a hard circular
    // cutout on the five-lobed specimen.
    float exterior = smoothstep(
        specimen_radius - transition_width * 0.60,
        specimen_radius + transition_width * 0.35,
        radius);
    float boundarySignal = smoothstep(
        boundary_floor,
        boundary_floor + boundary_softness,
        lum);
    float boundaryGate = lerp(
        1.0,
        boundarySignal,
        exterior * boundary_discipline);
    color *= boundaryGate;

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
