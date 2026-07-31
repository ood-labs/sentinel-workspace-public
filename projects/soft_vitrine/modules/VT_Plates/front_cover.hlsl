// VT_Plates / front_cover.hlsl — coverage lane for the front plate layer. The starfield panel is
// mostly black, so its coverage genuinely cannot be recovered from colour.
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> Src : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float c = saturate(Src[pixel].a);
    OutputUAV[pixel] = float4(c, c, c, 1.0);
}
