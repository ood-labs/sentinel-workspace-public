RWTexture2D<float4> OutputUAV : register(u0);

static const float FP_PI = 3.14159265359;

float fp_line(float value, float center, float width)
{
    return 1.0 - smoothstep(width, width * 2.2, abs(value - center));
}

float fp_box(float2 p, float2 center, float2 halfSize, float width)
{
    float2 d = abs(p - center) - halfSize;
    float outside = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    return 1.0 - smoothstep(width, width * 2.0, abs(outside));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float4 field = _Tex0.Load(int3(pixel, 0));
    float px = 1.0 / max(_Resolution.y, 1.0);

    float band = smoothstep(0.44 - band_width * 0.16, 0.49 - band_width * 0.08, field.r);
    float innerCut = smoothstep(0.78, 0.82, field.r);
    float paper = band * (1.0 - innerCut * (0.42 + rupture * 0.34));

    float contourA = fp_line(field.r, 0.24, px * (1.0 + stroke_width * 2.0));
    float contourB = fp_line(field.r, 0.67, px * (1.0 + stroke_width * 1.4));
    float structural = max(contourA * 0.34, contourB * 0.72);
    structural = max(structural, field.g * (0.18 + fault_tension * 0.24));

    float2 gridUv = uv * float2(16.0, 9.0);
    float2 gridCell = abs(frac(gridUv) - 0.5);
    float grid = max(
        1.0 - smoothstep(0.485, 0.499, gridCell.x),
        1.0 - smoothstep(0.485, 0.499, gridCell.y)
    );
    grid *= grid_strength * (0.28 + 0.72 * (1.0 - paper));

    float3 col = background_color;
    col = lerp(col, paper_color, saturate(paper * paper_gain));
    col = max(col, structural.xxx * paper_color * 0.82);
    col = max(col, grid.xxx * paper_color * 0.22);

    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 scar = scar_position * float2(aspect, 1.0);
    float incisionX = scar.x - 0.055 + sin((p.y - scar.y) * 5.0 + phase * FP_PI * 2.0) * (0.035 + rupture * 0.12);
    float incision = 1.0 - smoothstep(px * 1.2, px * (2.6 + accent_weight * 4.0), abs(p.x - incisionX));
    incision *= smoothstep(0.5, 0.96, field.g);
    incision += fp_box(p, scar + float2(-0.16, -0.28), float2(0.09, 0.035), px * 1.4) * 0.65;
    col = lerp(col, accent_color, saturate(incision * accent_weight));

    float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float frame = 1.0 - smoothstep(px * 2.0, px * 4.5, edge);
    col = max(col, frame.xxx * paper_color * 0.7);

    float cropTicks = 0.0;
    cropTicks = max(cropTicks, fp_box(uv, float2(0.08, 0.08), float2(0.036, 0.010), px));
    cropTicks = max(cropTicks, fp_box(uv, float2(0.92, 0.92), float2(0.036, 0.010), px));
    cropTicks = max(cropTicks, fp_box(uv, float2(0.92, 0.08), float2(0.010, 0.036), px));
    cropTicks = max(cropTicks, fp_box(uv, float2(0.08, 0.92), float2(0.010, 0.036), px));
    col = max(col, cropTicks.xxx * paper_color * 0.55);

    float vignette = smoothstep(0.9, 0.2, length((uv - 0.5) * float2(0.82, 1.0)));
    col *= lerp(0.72, 1.0, vignette);
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
