float luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float2 uv = In.Uv;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));

    float4 center = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float3 north = _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0, -texel.y)), 0).rgb;
    float3 south = _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0,  texel.y)), 0).rgb;
    float3 east  = _Tex0.SampleLevel(LinearSampler, saturate(uv + float2( texel.x, 0)), 0).rgb;
    float3 west  = _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(-texel.x, 0)), 0).rgb;

    float lumaCenter = luminance(center.rgb);
    float lumaMin = min(lumaCenter, min(min(luminance(north), luminance(south)),
                                        min(luminance(east), luminance(west))));
    float lumaMax = max(lumaCenter, max(max(luminance(north), luminance(south)),
                                        max(luminance(east), luminance(west))));
    float contrast = lumaMax - lumaMin;

    float3 neighborAverage = (north + south + east + west) * 0.25;
    float edgeBlend = smoothstep(0.008, 0.10, contrast) * aa_strength;
    float3 color = lerp(center.rgb, neighborAverage, edgeBlend * 0.42);

    return float4(color, center.a);
}
