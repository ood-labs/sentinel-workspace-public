// accum present — reads the persistent canvas buffer and writes it to the output texture.
StructuredBuffer<float4> Canvas : register(t0);     // input: buffer:canvas
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    uint W = (uint)_Resolution.x, H = (uint)_Resolution.y;
    if (px.x >= W || px.y >= H) return;
    uint idx = px.y * W + px.x;
    OutputUAV[px] = Canvas[idx];
}
