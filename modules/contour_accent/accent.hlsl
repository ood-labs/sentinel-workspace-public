// contour_accent — orange accent isolines DERIVED from the same Field, gated to
// selected levels (band / every-Nth / region / ridge). Reads Field (input:0).

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float4 f = _Tex0.Load(int3(pixel, 0));
    float h = f.r;
    float region = f.g;
    float slope = f.b;

    float phase = _Time * phase_speed;
    float fval = h * line_count + phase;
    float contour = abs(frac(fval) - 0.5);
    float ln = 1.0 - smoothstep(0.0, line_width, contour);
    float level = floor(fval);

    // gate: which contours become accents
    float g = 0.0;
    if (accent_mode == 0)        // elevation band
        g = smoothstep(band_width, 0.0, abs(h - accent_level));
    else if (accent_mode == 1)   // every Nth contour
        g = (fmod(level, max((float)accent_count, 1.0)) < 0.5) ? 1.0 : 0.0;
    else if (accent_mode == 2)   // region id band
        g = smoothstep(band_width, 0.0, abs(region - accent_level));
    else                          // ridge (high slope)
        g = smoothstep(accent_level, accent_level + band_width, slope);

    // optional index-tick dashing along the accent lines
    float dash = (index_ticks != 0)
        ? step(0.5, frac(((float)pixel.x + (float)pixel.y) * 0.05 + _Time * 0.5))
        : 1.0;

    float amt = ln * g * dash * intensity;
    float3 col = accent_color * amt * (1.0 + glow);

    OutputUAV[pixel] = float4(col, saturate(amt));
}
