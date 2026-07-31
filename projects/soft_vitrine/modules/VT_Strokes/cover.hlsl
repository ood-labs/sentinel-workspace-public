// VT_Strokes / cover.hlsl — the coverage lane. The near-black vein network is invisible in
// the colour lane against a dark stage, so this must be its own output.
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> Draw : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float c = saturate(Draw[pixel].a);
    OutputUAV[pixel] = float4(c, c, c, 1.0);
}
