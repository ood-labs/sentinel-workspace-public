RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    uint width;
    uint height;
    _Tex0.GetDimensions(width, height);
    if (pixel.x >= width || pixel.y >= height) return;

    float2 extent = float2((float)width, (float)height);
    float2 uv = ((float2)pixel + 0.5) / extent;
    float2 texel = 1.0 / max(extent, float2(1.0, 1.0));
    float aspect = extent.x / max(extent.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float3 relief = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 engraving = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float4 previous = _Tex2.SampleLevel(LinearSampler, uv, 0);

    float engravingLum = luminance(engraving);
    float engravingBlur =
        luminance(_Tex1.SampleLevel(LinearSampler, uv + float2(texel.x * 4.0, 0.0), 0).rgb) +
        luminance(_Tex1.SampleLevel(LinearSampler, uv - float2(texel.x * 4.0, 0.0), 0).rgb) +
        luminance(_Tex1.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * 4.0), 0).rgb) +
        luminance(_Tex1.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * 4.0), 0).rgb);
    engravingBlur *= 0.25;

    float cs = cos(section_angle);
    float sn = sin(section_angle);
    float2 sectionNormal = float2(cs, sn);

    // A complete pass takes roughly 6.7 seconds: fast enough to read as motion
    // instead of leaving the composition dormant and black.
    float travel = lerp(-1.05, 1.05, frac(_Time * 0.15));
    float guideOffset = (engravingLum - engravingBlur) * guide_warp;
    float signedDistance = dot(p, sectionNormal) - travel + guideOffset;
    float band = 1.0 - smoothstep(band_width, band_width * 1.75, abs(signedDistance));

    float decay = pow(saturate(retention), max(_DeltaTime, 0.0) * 60.0);
    float4 archived = previous * decay;
    archived.a = previous.a * decay;

    float reliefLum = luminance(relief);
    float guideEvidence = saturate(engravingLum * 6.0);
    float writeMask = saturate(band * write_strength * (0.72 + guideEvidence * 0.28));
    float3 sampled = relief * (0.92 + guideEvidence * 0.22);

    float4 written = float4(sampled, 1.0);
    float4 result = lerp(archived, written, writeMask);
    result.a = lerp(archived.a, 1.0, writeMask);

    // Preserve an extremely faint trace of bright relief immediately around
    // the section plane so a black sample still has a legible boundary.
    float halo = (1.0 - smoothstep(band_width * 1.7, band_width * 3.2, abs(signedDistance)));
    result.rgb += relief * halo * reliefLum * 0.025;

    OutputUAV[pixel] = float4(max(result.rgb, 0.0), saturate(result.a));
}
