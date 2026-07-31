// VT_Volumes / color.hlsl — publish the marched colour with an honest opaque alpha.
// Coverage is a SEPARATE output, because a black clay mass on a dark stage is not decidable
// from colour alone and must not be smuggled into this lane's alpha.
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> March : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    OutputUAV[pixel] = float4(March[pixel].rgb, 1.0);
}
