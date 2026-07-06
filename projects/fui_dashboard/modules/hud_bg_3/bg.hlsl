// hud_bg — FUI background wash: dark navy-teal base, faint reference grid,
// a few large faint guide arcs, and a soft vignette. Alpha = luminance so the
// compositor can treat it as the opaque base layer.

RWTexture2D<float4> OutputUAV : register(u0);

float gridLine(float coord, float spacing, float w)
{
    float f = frac(coord / spacing);
    float d = min(f, 1.0 - f) * spacing;
    return 1.0 - smoothstep(0.0, w, d);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 pc = (uv - 0.5) * float2(asp, 1.0);   // aspect-corrected, centre origin

    // vertical tonal gradient for the base
    float3 base = lerp(bg_top, bg_bottom, uv.y);

    // faint pixel grid
    float2 sp = float2(grid_spacing / _Resolution.x, grid_spacing / _Resolution.y);
    float gx = gridLine(uv.x, sp.x, sp.x * 0.10);
    float gy = gridLine(uv.y, sp.y, sp.y * 0.10);
    // heavier every 5th line
    float gX5 = gridLine(uv.x, sp.x * 5.0, sp.x * 0.5 * 0.10);
    float gY5 = gridLine(uv.y, sp.y * 5.0, sp.y * 0.5 * 0.10);
    float grid = max(gx, gy) * 0.4 + max(gX5, gY5) * 0.6;

    // large faint concentric guide arcs around the hero region
    float2 hc = (float2(0.72, 0.47) - 0.5) * float2(asp, 1.0);
    float rr = length(pc - hc);
    float arcs = 0.0;
    arcs += 1.0 - smoothstep(0.0, 0.003, abs(rr - 0.36));
    arcs += 1.0 - smoothstep(0.0, 0.003, abs(rr - 0.52));

    float3 col = base;
    col += grid_color * grid * grid_intensity;
    col += grid_color * arcs * grid_intensity * 0.6;

    // soft vignette (darken edges)
    float vig = 1.0 - vignette * dot(pc, pc) * 0.35;
    col *= saturate(vig);

    float lum = max(col.r, max(col.g, col.b));
    OutputUAV[pixel] = float4(col, lum);
}
