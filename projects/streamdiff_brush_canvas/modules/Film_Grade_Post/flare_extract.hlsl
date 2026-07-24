RWTexture2D<float4> OutputUAV : register(u0);

float3 prefilterHighlight(float3 color, float threshold)
{
    float brightness = max(color.r, max(color.g, color.b));
    float knee = max(0.06, threshold * 0.25);
    float soft = saturate((brightness - threshold + knee) / (2.0 * knee));
    soft = soft * soft * knee;
    float contribution = max(brightness - threshold, 0.0) + soft;
    return color * (contribution / max(brightness, 0.0001));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint outWidth, outHeight;
    OutputUAV.GetDimensions(outWidth, outHeight);
    uint2 pixel = DTid.xy;
    if (pixel.x >= outWidth || pixel.y >= outHeight) return;

    float2 uv = ((float2)pixel + 0.5) / float2(outWidth, outHeight);
    float3 color = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    OutputUAV[pixel] = float4(prefilterHighlight(color, flare_threshold), 1.0);
}
