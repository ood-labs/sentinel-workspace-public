// Adaptive_Mapping / am_view.hlsli - the Mapped Path canvas's geometry, from the live extent (the
// canvas follows its panel). draw.hlsl lands the path in `field`, preview.hlsl plates it, and
// layout.hlsl captions it, stacks the readouts beside it and hovers records through the same
// mapping, so what you see and what you inspect cannot disagree. Plain maths, no other includes.
//
//   head   title, mode and status
//   field  the scanner field, square (ILDA: -1..1, +y up)
//   side   the readout panes: beside the field when the panel is wide, under it when tall
//   foot   the verb
#ifndef AM_VIEW_HLSLI
#define AM_VIEW_HLSLI

struct AMLayout
{
    float  s;        // ui scale (type never below ~9 px)
    bool   beside;   // the panes stand right of the field (else they run under it)
    float4 head;
    float4 field;
    float4 side;
    float4 foot;
};

float amScale(float2 R) { return clamp(min(R.x / 900.0, R.y / 600.0), 0.86, 2.0); }

AMLayout amLayout(float2 R)
{
    AMLayout L;
    float s = amScale(R);
    L.s = s;
    float pad = 12.0 * s, headH = 40.0 * s, footH = 32.0 * s;
    L.head = float4(0.0, 0.0, R.x, headH);
    L.foot = float4(0.0, R.y - footH, R.x, R.y);
    float4 body = float4(pad, headH, R.x - pad, R.y - footH);
    float bw = body.z - body.x, bh = body.w - body.y;
    float sideW = clamp(0.32 * R.x, 210.0 * s, 300.0 * s);
    // beside when that still leaves the field at least 70 % of the body's height
    L.beside = bw - sideW - pad >= 0.7 * bh;
    float4 area;
    if (L.beside)
    {
        L.side = float4(body.z - sideW, body.y, body.z, body.w);
        area = float4(body.x, body.y, L.side.x - pad, body.w);
    }
    else
    {
        float sideH = clamp(0.42 * bh, 120.0 * s, 150.0 * s);
        L.side = float4(body.x, body.w - sideH, body.z, body.w);
        area = float4(body.x, body.y, body.z, L.side.y - pad);
    }
    float side = max(min(area.z - area.x, area.w - area.y), 48.0 * s);
    float2 c = 0.5 * (area.xy + area.zw);
    L.field = float4(c - 0.5 * side, c + 0.5 * side);
    return L;
}

// scanner space (-1..1, +y up) -> canvas px. The +-1 limits sit just inside the field plate.
#define AM_FIELD_FILL 0.47
float2 amFieldPx(AMLayout L, float2 q)
{
    float2 c = 0.5 * (L.field.xy + L.field.zw);
    float h = AM_FIELD_FILL * (L.field.z - L.field.x);
    return c + q * float2(h, -h);
}
float amFieldScale(AMLayout L) { return AM_FIELD_FILL * (L.field.z - L.field.x); }   // px per field unit

// The readout panes: 0 records, 1 tolerance, 2 cycle, 3 the records-out trace. A pane with no
// room comes back empty (zero height) and is skipped.
float4 amPane(AMLayout L, uint k)
{
    float s = L.s, gap = 8.0 * s;
    if (!L.beside)
    {
        float w = (L.side.z - L.side.x - 3.0 * gap) / 4.0;
        float x = L.side.x + (float)k * (w + gap);
        return w > 90.0 * s ? float4(x, L.side.y, x + w, L.side.w) : float4(0.0, 0.0, 0.0, 0.0);
    }
    float h01 = 96.0 * s, h2 = 116.0 * s;
    float y0 = L.side.y + (k >= 1u ? h01 + gap : 0.0) + (k >= 2u ? h01 + gap : 0.0) + (k >= 3u ? h2 + gap : 0.0);
    float y1 = k <= 1u ? y0 + h01 : (k == 2u ? y0 + h2 : L.side.w);
    bool fits = k <= 2u ? y1 <= L.side.w : y1 - y0 >= 84.0 * s;
    return fits ? float4(L.side.x, y0, L.side.z, y1) : float4(0.0, 0.0, 0.0, 0.0);
}

// row r of a pane (below its header strip), as a mid-line y
float amRowY(AMLayout L, float4 pane, uint r) { return pane.y + 26.0 * L.s + 6.0 * L.s + ((float)r + 0.5) * 20.0 * L.s; }

#endif
