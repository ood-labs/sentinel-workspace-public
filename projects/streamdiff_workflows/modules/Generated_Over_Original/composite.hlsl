RWTexture2D<float4> OutputUAV : register(u0);

float2 coverUv(float2 uv, float2 sourceSize, float2 targetSize)
{
    float sourceAspect = sourceSize.x / max(sourceSize.y, 1.0);
    float targetAspect = targetSize.x / max(targetSize.y, 1.0);

    if (sourceAspect > targetAspect)
        uv.x = (uv.x - 0.5) * (targetAspect / sourceAspect) + 0.5;
    else
        uv.y = (uv.y - 0.5) * (sourceAspect / targetAspect) + 0.5;

    return uv;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;

    uint generatedWidth;
    uint generatedHeight;
    _Tex1.GetDimensions(generatedWidth, generatedHeight);
    float2 generatedUv = coverUv(
        uv,
        float2(generatedWidth, generatedHeight),
        _Resolution.xy);

    float3 background = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 generated = _Tex1.SampleLevel(LinearSampler, generatedUv, 0).rgb;

    uint matteWidth;
    uint matteHeight;
    _Tex2.GetDimensions(matteWidth, matteHeight);
    float2 matteTexel = 1.0 / max(float2(matteWidth, matteHeight), float2(1.0, 1.0));
    float matteCenter = _Tex2.SampleLevel(LinearSampler, uv, 0).a;

    float grownMatte = matteCenter;
    if (abs(edge_grow) > 0.01)
    {
        float2 growStep = matteTexel * abs(edge_grow);
        float m0 = _Tex2.SampleLevel(LinearSampler, uv + float2( growStep.x, 0.0), 0).a;
        float m1 = _Tex2.SampleLevel(LinearSampler, uv + float2(-growStep.x, 0.0), 0).a;
        float m2 = _Tex2.SampleLevel(LinearSampler, uv + float2(0.0,  growStep.y), 0).a;
        float m3 = _Tex2.SampleLevel(LinearSampler, uv + float2(0.0, -growStep.y), 0).a;
        float m4 = _Tex2.SampleLevel(LinearSampler, uv + float2( growStep.x,  growStep.y), 0).a;
        float m5 = _Tex2.SampleLevel(LinearSampler, uv + float2(-growStep.x,  growStep.y), 0).a;
        float m6 = _Tex2.SampleLevel(LinearSampler, uv + float2( growStep.x, -growStep.y), 0).a;
        float m7 = _Tex2.SampleLevel(LinearSampler, uv + float2(-growStep.x, -growStep.y), 0).a;

        if (edge_grow > 0.0)
            grownMatte = max(matteCenter, max(max(max(m0, m1), max(m2, m3)), max(max(m4, m5), max(m6, m7))));
        else
            grownMatte = min(matteCenter, min(min(min(m0, m1), min(m2, m3)), min(min(m4, m5), min(m6, m7))));
    }

    float blurredMatte = matteCenter;
    if (edge_feather > 0.01)
    {
        float2 featherStep = matteTexel * edge_feather;
        float f0 = _Tex2.SampleLevel(LinearSampler, uv + float2( featherStep.x, 0.0), 0).a;
        float f1 = _Tex2.SampleLevel(LinearSampler, uv + float2(-featherStep.x, 0.0), 0).a;
        float f2 = _Tex2.SampleLevel(LinearSampler, uv + float2(0.0,  featherStep.y), 0).a;
        float f3 = _Tex2.SampleLevel(LinearSampler, uv + float2(0.0, -featherStep.y), 0).a;
        float f4 = _Tex2.SampleLevel(LinearSampler, uv + float2( featherStep.x,  featherStep.y), 0).a;
        float f5 = _Tex2.SampleLevel(LinearSampler, uv + float2(-featherStep.x,  featherStep.y), 0).a;
        float f6 = _Tex2.SampleLevel(LinearSampler, uv + float2( featherStep.x, -featherStep.y), 0).a;
        float f7 = _Tex2.SampleLevel(LinearSampler, uv + float2(-featherStep.x, -featherStep.y), 0).a;
        blurredMatte = matteCenter * 0.25
            + (f0 + f1 + f2 + f3 + f4 + f5 + f6 + f7) * 0.09375;
    }

    float refinedMatte = saturate(blurredMatte + (grownMatte - matteCenter));
    float matte = pow(refinedMatte, max(matte_gamma, 0.01));
    matte *= foreground_opacity;
    float3 composited = lerp(background, generated, saturate(matte));

    OutputUAV[tid.xy] = float4(composited, 1.0);
}
