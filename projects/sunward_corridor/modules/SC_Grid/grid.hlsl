// SC_Grid / grid.hlsl — the finish.
//
// The reference is not a clean render, and pretending otherwise loses half of what makes it
// look the way it does. It has been through something: the image is quantized onto a coarse
// pixel grid, individual COLUMNS are stretched into long vertical runs, gradients band into
// visible steps, and the whole thing sits inside a hard black frame.
//
// This node is that pass and nothing else. It changes no geometry, no palette and no
// composition — if something in here would change what the image IS, it belongs upstream in
// SC_Plan (placement, sun, travel) or SC_Corridor (form, light, material).
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> Src : register(t0);

#define TAP(UV) Src[clamp(int2((UV) * _Resolution.xy), int2(0, 0), \
                          int2((int)_Resolution.x - 1, (int)_Resolution.y - 1))]

float gh(float n, float k) { return frac(sin(n * 12.9898 + k * 78.233) * 43758.5453); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pix = DTid.xy;
    if (pix.x >= (uint)_Resolution.x || pix.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pix + 0.5) / _Resolution.xy;

    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float cols = max(grid_cols, 4.0);
    float cellW = 1.0 / cols;
    float baseRowH = cellW * aspect;            // square cells before any stretch
    int mode = (int)grain_mode;

    float cx = floor(uv.x * cols);
    float2 samp = uv;

    if (mode == 2)
    {
        // Scanline Drift — whole ROWS displaced sideways. Square cells, torn horizontally.
        float ry = floor(uv.y / baseRowH);
        float drift = (gh(ry, 5.1) - 0.5) * smear * 0.09;
        samp.x = uv.x + drift;
        cx = floor(samp.x * cols);
        samp = float2((cx + 0.5) * cellW, (ry + 0.5) * baseRowH);
    }
    else
    {
        // Column Smear (and the Clean Grid / Mosaic cases, which just take smear to zero).
        // Each column gets its own block height, squared so most columns stay near square and
        // a few run long — an even spread of stretch reads as a blur, not as an artifact.
        float hs = gh(cx, 1.7);
        float stretch = (mode == 0) ? 0.0 : (1.0 + smear * hs * hs * 7.0);
        float rowH = baseRowH * max(stretch, 1.0);
        float voff = gh(cx, 3.3) * rowH;
        float cy = floor((uv.y + voff) / rowH);
        float xj = (mode == 1) ? (gh(cx, 9.7) - 0.5) * smear * cellW * 1.6 : 0.0;
        samp = float2((cx + 0.5) * cellW + xj, (cy + 0.5) * rowH - voff);
    }

    // Per-column chroma split. Real subsampled colour breaks up on block boundaries rather
    // than smoothly, so the offset is quantized to the grid too.
    float coff = (gh(cx, 21.3) - 0.5) * chroma * cellW * 2.0;
    float3 col;
    col.r = TAP(samp + float2(coff, 0.0)).r;
    col.g = TAP(samp).g;
    col.b = TAP(samp - float2(coff, 0.0)).b;

    if (mode == 3)
    {
        // Mosaic Bleed — each block averages its horizontal neighbours, so colour runs
        // sideways along the grid and the palette starts to smear into new intermediates.
        float3 l = TAP(samp - float2(cellW, 0.0)).rgb;
        float3 r = TAP(samp + float2(cellW, 0.0)).rgb;
        col = lerp(col, (l + r + col) / 3.0, saturate(smear));
    }

    // Posterize. Done on the already-quantized sample so the banding lands ON the grid rather
    // than cutting across it — that alignment is most of why the reference reads as one
    // process rather than as two filters stacked.
    float lv = max(levels, 2.0);
    col = floor(saturate(col) * lv + 0.5) / lv;

    col = lerp(col, saturate(col * gain), 1.0);

    // Hard black frame. Not a vignette — the reference has a literal border with a crisp edge.
    float2 d = abs(uv - 0.5) - (0.5 - float2(frame / aspect, frame));
    float inFrame = 1.0 - step(0.0, max(d.x, d.y));
    col *= inFrame;

    OutputUAV[pix] = float4(col, 1.0);
}
