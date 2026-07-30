struct PosterPixel {
    float4 color;
    float4 meta;
};

StructuredBuffer<PosterPixel> Poster : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;
    uint index = id.y * 1080u + id.x;
    float mask = saturate(Poster[index].color.a);
    OutputUAV[id.xy] = float4(mask, mask, mask, 1.0);
}
