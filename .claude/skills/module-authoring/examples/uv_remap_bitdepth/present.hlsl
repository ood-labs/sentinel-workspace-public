// Pass 2 of the UV Remap Bit Depth Test.
//
// Read the stored float coordinates (slot 0 = pass:store_uv) and sample a very
// high-frequency procedural pattern through them. The high frequency is what makes
// precision visible: with continuous 32-bit coordinates the pattern is smooth, but
// if the coordinates were quantized to 8-bit (256 levels) the pattern stair-steps
// into visible bands because many output pixels collapse onto the same coordinate.
//
// Output is plain 8-bit (the manifest sets this pass to RGBA8 and routes it to the
// pipeline output).

float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float2 uv = _Tex0.SampleLevel(PointSampler, In.Uv, 0).rg;

    // Fine concentric rings + a fine grid. ~250-400 cycles across [0,1] means an
    // 8-bit coordinate (1/256 steps) cannot resolve a smooth sweep and visibly bands.
    float r     = length(uv - 0.5);
    float rings = 0.5 + 0.5 * sin(r * 320.0);
    float gridX = 0.5 + 0.5 * sin(uv.x * 400.0);
    float gridY = 0.5 + 0.5 * sin(uv.y * 400.0);

    float3 col = float3(rings, gridX * gridY, frac(uv.x * 16.0));
    return float4(saturate(col), 1.0);
}
