struct PosterPixel {
    float4 color;
    float4 meta;
};
StructuredBuffer<PosterPixel> Poster : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float3 pcHsv2rgb(float3 c)
{
    float3 p = abs(frac(c.xxx + float3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
    return c.z * lerp(1.0.xxx, saturate(p - 1.0), c.y);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;
    uint index = id.y * 1080u + id.x;
    float4 paint = Poster[index].color;
    float3 background = pcHsv2rgb(float3(background_hue, background_saturation, background_value));
    float3 color = paint.rgb + background * (1.0 - saturate(paint.a));
    OutputUAV[id.xy] = float4(saturate(color), 1.0);
}
