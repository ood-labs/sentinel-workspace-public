// face_tiles — rectangular photo-patchwork of the face. Partitions the frame into an irregular
// grid of rectangles; each tile samples the face (_Tex0) with a per-tile crop shift/zoom and a
// per-tile tone mismatch (brightness/contrast/hue), separated by hard seams — the "many photos
// stitched" collage base. ps_5_0 fullscreen; injected VS_OUTPUT{Position,Uv}.

static const int NCB = 5;   // 4 columns
static const int NRB = 6;   // 5 rows
static const float COLB[5] = { 0.0, 0.30, 0.55, 0.76, 1.0 };
static const float ROWB[6] = { 0.0, 0.17, 0.34, 0.53, 0.73, 1.0 };

float h21(float2 p){ return frac(sin(dot(p, float2(127.1, 311.7)) + seed * 1.7) * 43758.5453); }

float3 hue(float3 c, float a)
{
    float3 k = float3(0.57735, 0.57735, 0.57735);
    float cosA = cos(a);
    return c * cosA + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cosA);
}

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;

    // locate the tile (irregular rectangle) containing uv
    int ci = 0; [unroll] for (int i = 0; i < NCB - 1; i++) if (uv.x >= COLB[i]) ci = i;
    int ri = 0; [unroll] for (int j = 0; j < NRB - 1; j++) if (uv.y >= ROWB[j]) ri = j;
    float x0 = COLB[ci], x1 = COLB[ci + 1];
    float y0 = ROWB[ri], y1 = ROWB[ri + 1];
    float2 cellMin = float2(x0, y0), cellMax = float2(x1, y1);
    float2 cellSize = cellMax - cellMin;
    float2 fCell = (uv - cellMin) / max(cellSize, 1e-4);        // 0..1 within tile

    float2 cid = float2((float)ci, (float)ri);
    float ho = h21(cid + 3.1);
    float hs = h21(cid + 7.7);
    float ht = h21(cid + 11.3);
    float hh = h21(cid + 17.9);

    // per-tile crop: zoom + shift the sampled region of the face
    float zoom = lerp(1.0 - crop_zoom, 1.0 + crop_zoom, hs);
    float2 shift = (float2(ho, ht) - 0.5) * crop_shift;
    // sample the face at the tile's own footprint, re-anchored so features roughly stay put,
    // then nudged by the per-tile shift/zoom for the mismatch
    float2 sampleUV = (uv - 0.5) * zoom + 0.5 + shift;
    float3 col = _Tex0.SampleLevel(LinearSampler, saturate(sampleUV), 0).rgb;

    // per-tile tone mismatch
    float bright = lerp(1.0 - tone_amt, 1.0 + tone_amt, ht);
    float contr  = lerp(1.0 - tone_amt * 0.6, 1.0 + tone_amt * 0.6, hs);
    col = (col - 0.5) * contr + 0.5;
    col *= bright;
    col = hue(col, (hh - 0.5) * hue_amt);
    col = saturate(col);

    // hard seams at tile borders
    float2 pxw = fwidth(uv) * seam_width;
    float2 edge = min(uv - cellMin, cellMax - uv);
    float seam = 1.0 - smoothstep(0.0, max(pxw.x, pxw.y), min(edge.x, edge.y));
    col = lerp(col, float3(seam_r, seam_g, seam_b), seam * seam_opacity);

    return float4(col, 1.0);
}
