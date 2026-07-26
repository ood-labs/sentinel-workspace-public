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

float2 panelUV(float2 uv, float2 center, float2 halfSize)
{
    return (uv - center) / max(halfSize * 2.0, 0.0001) + 0.5;
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
    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float2 topCenter = float2(0.43, 0.075);
    float2 topHalf = float2(0.105, 0.064);
    float2 leftCenter = float2(0.075, 0.42);
    float2 leftHalf = float2(0.064, 0.145);

    float topBacking = boxMask(uv, topCenter, topHalf + float2(0.009, 0.011), 0.003);
    float leftBacking = boxMask(uv, leftCenter, leftHalf + float2(0.010, 0.009), 0.003);
    float topPlate = boxMask(uv, topCenter, topHalf, 0.003);
    float leftPlate = boxMask(uv, leftCenter, leftHalf, 0.003);

    // Stack literal black backings before laying the earlier signal on top.
    float backing = saturate(max(topBacking, leftBacking));
    col *= 1.0 - backing * 0.985;

    float drift = _Time * relay_rate;
    float2 topLocal = panelUV(uv, topCenter, topHalf);
    float2 topSampleUV = (topLocal - 0.5) / insert_scale + 0.5;
    topSampleUV.x = frac(topSampleUV.x + drift);
    topSampleUV.y = saturate(topSampleUV.y);

    float2 leftLocal = panelUV(uv, leftCenter, leftHalf);
    float2 leftSampleUV = float2(leftLocal.y, 1.0 - leftLocal.x);
    leftSampleUV = (leftSampleUV - 0.5) / insert_scale + 0.5;
    leftSampleUV.x = frac(leftSampleUV.x - drift * 0.78);
    leftSampleUV.y = saturate(leftSampleUV.y);

    float3 topSignal = _Tex1.SampleLevel(LinearSampler, topSampleUV, 0).rgb;
    float3 leftSignal = _Tex1.SampleLevel(LinearSampler, leftSampleUV, 0).rgb;
    topSignal = pow(saturate(topSignal), 0.72) * insert_gain;
    leftSignal = pow(saturate(leftSignal), 0.72) * insert_gain;

    // Each plate is opaque and spatially reframed. No source-value gate is
    // involved; the masks describe only the physical plate rectangles.
    col = lerp(col, topSignal, topPlate);
    col = lerp(col, leftSignal, leftPlate);

    float topEdge = saturate(topBacking - topPlate);
    float leftEdge = saturate(leftBacking - leftPlate);
    float edge = saturate(max(topEdge, leftEdge));
    float sourceEnergy = saturate(luminance(topSignal) + luminance(leftSignal));
    col += edge * border_gain * (0.18 + sourceEnergy * 0.12) *
           float3(0.74, 0.76, 0.72);

    col = 1.0 - exp(-max(col, 0.0));
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
