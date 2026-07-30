// Pass 1 of the UV Remap Bit Depth Test.
//
// Read the UV map (slot 0, _Tex0) and store its R/G coordinates into this pass's
// render target. The manifest's working_format pins that RT to RGBA32F, so a
// 32-bit float UV input survives this hop at full precision. If the RT were 8-bit
// (an 8-bit intermediate), the coordinates would be quantized to 256 levels
// here, before the present pass ever samples through them.
//
// _Tex0 (Texture2D<float4>), PointSampler, and VS_OUTPUT (.Uv) are injected by the
// module compiler.

float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float2 uv = _Tex0.SampleLevel(PointSampler, In.Uv, 0).rg;
    return float4(uv, 0.0, 1.0);
}
