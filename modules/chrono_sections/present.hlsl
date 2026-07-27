RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float boxMask(float2 uv, float2 center, float2 halfSize, float feather)
{
    float2 d = abs(uv - center) - halfSize;
    float signedEdge = max(d.x, d.y);
    return 1.0 - smoothstep(-feather, feather, signedEdge);
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

    float4 archive = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float3 relief = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 engraving = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;

    float ageL = _Tex0.SampleLevel(LinearSampler, uv - float2(texel.x * 2.0, 0.0), 0).a;
    float ageR = _Tex0.SampleLevel(LinearSampler, uv + float2(texel.x * 2.0, 0.0), 0).a;
    float ageU = _Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * 2.0), 0).a;
    float ageD = _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * 2.0), 0).a;
    float sectionSeam = saturate((abs(ageR - ageL) + abs(ageD - ageU)) * seam_gain);

    float engravingLum = luminance(engraving);
    float engrL = luminance(_Tex2.SampleLevel(LinearSampler, uv - float2(texel.x * 2.0, 0.0), 0).rgb);
    float engrR = luminance(_Tex2.SampleLevel(LinearSampler, uv + float2(texel.x * 2.0, 0.0), 0).rgb);
    float engrU = luminance(_Tex2.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * 2.0), 0).rgb);
    float engrD = luminance(_Tex2.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * 2.0), 0).rgb);
    float registrationEdge = saturate((abs(engrR - engrL) + abs(engrD - engrU)) * 2.2);

    // The source remains present continuously. The archive is an additive
    // temporal layer, not a thresholded replacement for the current image.
    float3 reliefLift = pow(saturate(relief), 0.82);
    float3 engravingLift = pow(saturate(engraving), 0.76);
    float3 col = reliefLift * 0.58;
    col += archive.rgb * archive_gain;
    float archiveLum = luminance(archive.rgb);
    float warmEvidence = saturate(archive.r - max(archive.g, archive.b) * 1.04);
    col += float3(0.96, 0.14, 0.025) * warmEvidence * warm_hold;

    col += engravingLift * current_ghost;
    float currentWarm = saturate(engraving.r - max(engraving.g, engraving.b) * 1.04);
    col += float3(0.96, 0.14, 0.025) * currentWarm * warm_hold * 0.46;

    col += registrationEdge * registration * float3(0.42, 0.44, 0.41);
    col += sectionSeam * float3(0.54, 0.57, 0.53);

    // Four unequal architectural slabs carve a stable asymmetrical hierarchy.
    // They are literal opaque layers; the source remains untouched underneath.
    float slabTop = boxMask(uv, float2(0.43, 0.075),
                            float2(0.115, 0.075), 0.004);
    float slabLeft = boxMask(uv, float2(0.075, 0.42),
                             float2(0.075, 0.155), 0.004);
    float slabRight = boxMask(uv, float2(0.875, 0.61),
                              float2(0.125, 0.105), 0.004);
    float slabBottom = boxMask(uv, float2(0.57, 0.91),
                               float2(0.145, 0.09), 0.004);

    // A narrow dark section crosses the static slabs in about 6.7 seconds.
    // It reads as a cut through the object, never as a long blackout.
    float cs = cos(section_angle);
    float sn = sin(section_angle);
    float2 sectionNormal = float2(cs, sn);
    float travel = lerp(-1.05, 1.05, frac(_Time * 0.15));
    float movingCut = 1.0 - smoothstep(0.048, 0.074,
                                      abs(dot(p, sectionNormal) - travel));

    float structuralVoid = saturate(max(max(slabTop, slabLeft),
                                        max(slabRight, slabBottom)));
    col *= 1.0 - structuralVoid * void_depth;
    col *= 1.0 - movingCut * 0.74;

    float vignette = 1.0 - smoothstep(0.55, 1.04, length(p));
    col *= 0.84 + 0.16 * vignette;
    col = 1.0 - exp(-col * exposure);
    col = pow(saturate(col), 1.0 / 1.12);
    col += float3(0.0010, 0.0011, 0.0010);

    OutputUAV[pixel] = float4(col, 1.0);
}
