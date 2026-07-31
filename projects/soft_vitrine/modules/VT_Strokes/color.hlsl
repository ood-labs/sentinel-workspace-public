// VT_Strokes / color.hlsl — opaque colour lane.
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> Draw : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    OutputUAV[pixel] = float4(Draw[pixel].rgb, 1.0);
}
