// pl_path preview — placeholder texture output (Nodes consumed via data port).
RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    OutputUAV[pixel] = float4(0.0, 0.06, 0.04, 1.0);
}
