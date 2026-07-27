RWTexture2D<float4> OutputUAV : register(u0);

float luminance_proxy(float3 c)
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
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));

    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float l = luminance_proxy(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb);
    float r = luminance_proxy(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb);
    float u = luminance_proxy(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb);
    float d = luminance_proxy(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb);

    float gradient = length(float2(r - l, d - u));
    float redDominance = max(0.0, c.r - max(c.g, c.b));
    float response = gradient * edge_gain + redDominance * red_emphasis;
    float edge = smoothstep(edge_threshold, edge_threshold + 0.09, response);

    float3 color = edge * float3(0.86, 0.88, 0.84);
    float redMark = smoothstep(0.12, 0.42, redDominance) * edge;
    color = lerp(color, float3(1.0, 0.19, 0.035), redMark * 0.82);

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
