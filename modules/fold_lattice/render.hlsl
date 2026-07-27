RWTexture2D<float4> OutputUAV : register(u0);

float lineMask(float d, float width)
{
    return 1.0 - smoothstep(width, width * 2.4, abs(d));
}

float2 rotate2(float2 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / max(_Resolution.y, 1.0);
    float t = _Time;

    float2 slowDrift = float2(
        fbm2D(p * 0.72 + float2(t * 0.031, -t * 0.019), 3),
        fbm2D(p * 0.83 + float2(-t * 0.023, t * 0.027), 3)
    ) - 0.5;
    float radial = length(p);
    float angle = atan2(p.y, p.x);

    float2 folded = rotate2(p, 0.19 * sin(t * 0.11));
    folded += slowDrift * (0.18 + fold_amount * 0.12);
    folded += normalize(p + float2(0.0001, 0.0)) * radial_bias * 0.16;

    float2 cellUv = folded * lattice_density;
    float2 cellId = floor(cellUv);
    float2 cell = frac(cellUv) - 0.5;
    float cellSeed = hash21(cellId + 47.0);

    float chevron = abs(cell.x) + abs(cell.y);
    float cellEdge = min(abs(abs(cell.x) - 0.5), abs(abs(cell.y) - 0.5));
    float foldedBand = abs(frac(
        chevron * (2.0 + fold_amount * 1.7)
        + radial * 1.8
        + cellSeed * 0.19
        - t * 0.045
    ) - 0.5);

    float contourField =
        sin(folded.x * (11.0 + lattice_density * 0.42) + sin(angle * 3.0 - t * 0.17) * fold_amount)
        + sin(folded.y * (13.0 + lattice_density * 0.31) - cos(angle * 5.0 + t * 0.13) * fold_amount)
        + sin((folded.x - folded.y) * 8.0 + radial * 5.0 - t * 0.21);

    float contour = lineMask(abs(contourField) - aperture, px * (8.0 + line_weight * 7.0));
    float grid = 1.0 - smoothstep(px * line_weight * 1.5, px * line_weight * 3.5, cellEdge / lattice_density);
    float facets = 1.0 - smoothstep(0.018, 0.045, foldedBand);

    float ringCoord = radial * (16.0 + lattice_density * 0.35) - t * 0.12;
    float registration = lineMask(abs(frac(ringCoord) - 0.5) - 0.475, px * 0.75);
    registration *= smoothstep(0.08, 0.18, radial) * (1.0 - smoothstep(0.47, 0.78, radial));

    float rare = step(0.88, cellSeed) * facets;
    float scan = 1.0 - smoothstep(px * 1.4, px * 4.5, abs(p.y - 0.19 * sin(p.x * 2.7 + t * 0.15)));
    scan *= 0.35 + 0.65 * step(0.68, fbm2D(float2(p.x * 5.0 - t * 0.09, 3.1), 3));

    float vignette = 1.0 - smoothstep(0.48, 0.86, radial);
    float3 background = float3(0.003, 0.004, 0.0045);
    background += float3(0.012, 0.013, 0.014) * (1.0 - vignette);

    float whiteInk = saturate(contour * 0.88 + grid * 0.30 + registration * 0.34);
    whiteInk *= 0.55 + 0.45 * vignette;
    float3 col = background + whiteInk * float3(0.78, 0.80, 0.78);

    float accentMask = saturate(rare * 0.85 + scan * 0.65);
    accentMask *= saturate(0.4 + contour * 0.8);
    col = lerp(col, accent_color, accentMask);

    float crossX = lineMask(abs(p.x) - 0.0035, px * 0.7) * (1.0 - smoothstep(0.025, 0.055, abs(p.y)));
    float crossY = lineMask(abs(p.y) - 0.0035, px * 0.7) * (1.0 - smoothstep(0.025, 0.055, abs(p.x)));
    col += (crossX + crossY) * float3(0.62, 0.64, 0.62);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
