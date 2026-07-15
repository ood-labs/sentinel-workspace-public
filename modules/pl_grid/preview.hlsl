// pl_grid preview — placeholder texture output (placement consumed via Nodes port).
RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    OutputUAV[pixel] = float4(0.0, 0.05, 0.06, 1.0);
}
