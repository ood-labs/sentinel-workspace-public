// contour_blue — blue elevation isolines sliced from the shared Field texture.
// Reads Field (input:0): R=elevation, B=slope. Emits glowing contour lines (RGBA16F).

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float4 f = _Tex0.Load(int3(pixel, 0));
    float h = f.r;
    float slope = f.b;

    float phase = _Time * phase_speed;
    float fval = h * line_count + phase;
    float contour = abs(frac(fval) - 0.5);

    // wider lines where terrain is flat (low slope) reads more like real topo maps
    float lw = line_width * (1.0 + slope_warp * (1.0 - saturate(slope)));
    float ln = 1.0 - smoothstep(0.0, lw, contour);
    ln = pow(saturate(ln), 1.0 + sharpness * 4.0);

    // major / minor emphasis
    float level = floor(fval);
    float isMajor = step(0.5, 1.0 - abs(frac(level / max((float)major_every, 1.0)) - 0.0));
    isMajor = (fmod(level, max((float)major_every, 1.0)) < 0.5) ? 1.0 : 0.0;
    float boost = lerp(1.0, major_boost, isMajor);

    // elevation gate + fade
    float gate = step(min_level, h) * step(h, max_level);
    float fade = lerp(1.0, saturate(0.2 + h), elevation_fade);

    float amt = ln * boost * gate * fade * intensity;
    float3 col = lerp(blue_color, major_color, isMajor) * amt;

    OutputUAV[pixel] = float4(col, saturate(amt));
}
