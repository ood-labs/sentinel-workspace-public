RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;
    float depth = saturate(_Tex0.Load(int3(id.xy, 0)).a);
    OutputUAV[id.xy] = float4(depth, depth, depth, 1.0);
}
