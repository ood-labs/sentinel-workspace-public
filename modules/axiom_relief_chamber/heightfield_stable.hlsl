RWTexture2D<float4> OutputUAV : register(u0);

float reliefLuma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint outputWidth = 0;
    uint outputHeight = 0;
    OutputUAV.GetDimensions(outputWidth, outputHeight);
    if (tid.x >= outputWidth || tid.y >= outputHeight) return;

    float2 uv = ((float2)tid.xy + 0.5) / float2(outputWidth, outputHeight);

    uint sourceWidth = 0;
    uint sourceHeight = 0;
    _Tex1.GetDimensions(sourceWidth, sourceHeight);
    float2 sourceTexel = 1.0 / max(float2(sourceWidth, sourceHeight), float2(1.0, 1.0));

    float organicCenter = reliefLuma(_Tex1.SampleLevel(LinearSampler, uv, 0).rgb);
    float organicCross = reliefLuma(_Tex1.SampleLevel(LinearSampler, uv + float2(sourceTexel.x, 0.0), 0).rgb)
                       + reliefLuma(_Tex1.SampleLevel(LinearSampler, uv - float2(sourceTexel.x, 0.0), 0).rgb)
                       + reliefLuma(_Tex1.SampleLevel(LinearSampler, uv + float2(0.0, sourceTexel.y), 0).rgb)
                       + reliefLuma(_Tex1.SampleLevel(LinearSampler, uv - float2(0.0, sourceTexel.y), 0).rgb);
    float organic = organicCenter * 0.52 + organicCross * 0.12;
    float programInk = reliefLuma(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb);
    float featureEdge = reliefLuma(_Tex2.SampleLevel(LinearSampler, uv, 0).rgb);

    float aspect = (float)sourceWidth / max((float)sourceHeight, 1.0);
    float kineticBump = 0.0;
    float kineticCore = 0.0;
    uint eventCount = min(_Data0_Count, 64u);
    [loop]
    for (uint i = 0u; i < eventCount; ++i)
    {
        if (_Data0[i].active < 0.5) continue;
        float2 delta = (uv - _Data0[i].position) * float2(aspect, 1.0);
        float eventRadius = impact_radius * (0.72 + _Data0[i].energy * 0.72);
        float normalizedRadius = length(delta) / max(eventRadius, 0.001);
        float cone = saturate(1.0 - normalizedRadius);
        kineticBump = max(kineticBump, cone * cone * saturate(_Data0[i].energy));
        kineticCore = max(kineticCore,
                          smoothstep(0.34, 0.02, normalizedRadius)
                          * saturate(_Data0[i].energy));
    }

    float terrainHeight = organic * 0.48
                        + pow(saturate(programInk), 1.35) * 0.20
                        + featureEdge * edge_ridge
                        + kineticBump * impact_height;
    terrainHeight = saturate(terrainHeight);
    float safeTerraces = max((float)terrace_steps, 2.0);
    float terraced = floor(terrainHeight * safeTerraces + 0.5) / safeTerraces;
    float currentHeight = lerp(terrainHeight, terraced, terrace_mix);
    float currentKinetic = saturate(max(kineticBump, kineticCore));

    float4 previousField = _Tex3.SampleLevel(LinearSampler, uv, 0);
    float retention = saturate(height_stability);
    float heightRetention = retention;
    float ridgeRetention = retention * 0.88;
    float kineticRetention = retention * 0.72;
    float organicRetention = retention * 0.90;

    float stableHeight = lerp(currentHeight, previousField.r, heightRetention);
    float stableRidge = lerp(saturate(featureEdge), previousField.g, ridgeRetention);
    float stableKinetic = lerp(currentKinetic, previousField.b, kineticRetention);
    float stableOrganic = lerp(saturate(organic), previousField.a, organicRetention);

    OutputUAV[tid.xy] = float4(stableHeight, stableRidge, stableKinetic, stableOrganic);
}
