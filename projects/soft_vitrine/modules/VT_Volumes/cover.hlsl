// VT_Volumes / cover.hlsl — the real coverage lane the compositor layers, shadows and
// floor-reflects against. White = mass, black = empty stage.
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> March : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float c = saturate(March[pixel].a);
    OutputUAV[pixel] = float4(c, c, c, 1.0);
}
