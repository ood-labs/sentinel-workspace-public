RWTexture2D<float4> OutputUAV : register(u0);

float vacuum_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float vacuum_segment_distance(float2 p, float2 a, float2 b)
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
    float2 texel = 1.0 / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float2 p = (uv - float2(0.5, 0.5) - vacuum_core) * float2(aspect, 1.0);
    float radius = length(p);
    float theta = atan2(p.y, p.x);

    // Let the local contour field make a restrained six-facet perturbation,
    // while keeping the excision fundamentally clean and centrally legible.
    float lumX0 = vacuum_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x * 3.0, 0.0), 0).rgb);
    float lumX1 = vacuum_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x * 3.0, 0.0), 0).rgb);
    float lumY0 = vacuum_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * 3.0), 0).rgb);
    float lumY1 = vacuum_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * 3.0), 0).rgb);
    float2 fieldGradient = float2(lumX1 - lumX0, lumY1 - lumY0);
    float fieldPhase = dot(normalize(p + float2(1e-5, 0.0)), fieldGradient);
    float facet = cos(theta * 6.0 + fieldPhase * 1.35);
    float shapedRadius = void_radius * (1.0 + facet * facet_depth);

    float innerRelease = smoothstep(
        shapedRadius - edge_feather,
        shapedRadius + edge_feather,
        radius);
    float penumbraReturn = smoothstep(
        shapedRadius + edge_feather,
        shapedRadius + edge_feather + penumbra_width,
        radius);
    float sourceLum = vacuum_luma(source);
    float contourCarrier = lerp(
        penumbra_residue,
        1.0,
        smoothstep(
            penumbra_floor,
            penumbra_floor + penumbra_softness,
            sourceLum));
    float penumbraGate = lerp(contourCarrier, 1.0, penumbraReturn);
    float outside =
        innerRelease *
        lerp(1.0, penumbraGate, penumbra_discipline);
    float3 nucleus = source * nucleus_floor;
    float3 color = lerp(nucleus, source, outside);

    // Give the excision a shallow physical lip without drawing a synthetic
    // ring. Relief only modulates source material already present at the
    // boundary: one side catches restrained light while the opposite side
    // recedes, leaving the true nucleus black.
    float lipDistance = abs(radius - shapedRadius);
    float lipBand = 1.0 - smoothstep(
        edge_feather * 0.30,
        edge_feather + nucleus_lip_width,
        lipDistance);
    float lipOutside = smoothstep(
        shapedRadius - edge_feather,
        shapedRadius + edge_feather * 1.35,
        radius);
    float2 lipNormal = normalize(p + float2(1e-5, 0.0));
    float lipIncidence = dot(
        lipNormal,
        normalize(float2(-0.58, -0.82)));
    float lipPresence = lipBand * lipOutside;
    color *=
        1.0 +
        lipPresence *
            max(lipIncidence, 0.0) *
            nucleus_lip_relief;
    color *=
        1.0 -
        lipPresence *
            max(-lipIncidence, 0.0) *
            nucleus_lip_shadow;

    // Restore only the real stabilized azimuth through the void so the
    // excision improves its legibility without adding a second motif.
    float2 direction = normalize(float2(azimuth_x, azimuth_y) + float2(1e-5, 0.0));
    float needleDistance = vacuum_segment_distance(p, direction * 0.012, direction * 0.285);
    float needle = 1.0 - smoothstep(1.1 / _Resolution.y, 2.45 / _Resolution.y, needleDistance);
    needle *= smoothstep(0.08, 0.45, azimuth_confidence) * needle_restore;
    color = lerp(color, float3(1.0, 0.105, 0.018), needle);

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
