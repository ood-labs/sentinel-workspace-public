// ka_ui.hlsli - kuka_cell's thin layer over the shared UI kit (_shared/ui/il_*.hlsli).
//
// The three instrument canvases (KA_Cell, KA_Rally, KA_Pose) lay out on a 1024 x 640 reference: at
// that extent one ui unit is one pixel, and a larger or smaller output scales the whole layout with
// it. The floor keeps the smallest caption at 9 px. Art passes use only the scale; the helpers below
// need the draw list, so they exist only after il_draw.hlsli (layout passes).
#ifndef KA_UI_HLSLI
#define KA_UI_HLSLI

float kaUiScale(float2 res) { return clamp(min(res.x / 1024.0, res.y / 640.0), 0.86, 2.4); }

#ifdef IL_DRAW_HLSLI
// A key and what it does, for a footer. Returns the width used.
float kaHintW(float s, uint key, uint does)
{
    return ilLabelW(key, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(does, IL_T_CAP * s) + 16.0 * s;
}
float kaHint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

// A state tag: a short label on a lifted face, edged in the colour of what it says (EDITED in rule,
// CLASH in alarm). Returns the width used.
float kaTag(float x, float y, float s, uint label, float3 ink, float3 edge)
{
    float w = ilLabelW(label, IL_T_CAP * s) + 12.0 * s;
    dlRectEdged(float4(x, y - 8.0 * s, x + w, y + 8.0 * s), IL_RAISE, 1.0, IL_RADIUS * s, edge, 1.0);
    dlLabel(label, x + 6.0 * s, y, IL_T_CAP * s, ink, IL_LEFT);
    return w + 6.0 * s;
}

// A hover card of size sz beside an anchor, flipped away from the edges of bounds so it never
// leaves the canvas, drawn as a lifted face. Returns its rect.
float4 kaCard(float2 anchor, float2 sz, float4 bounds, float s)
{
    float gap = 14.0 * s;
    float x = anchor.x + gap;
    if (x + sz.x > bounds.z - 4.0 * s) x = anchor.x - gap - sz.x;
    x = clamp(x, bounds.x + 4.0 * s, max(bounds.z - 4.0 * s - sz.x, bounds.x + 4.0 * s));
    float y = anchor.y - sz.y - gap;
    if (y < bounds.y + 4.0 * s) y = anchor.y + gap;
    y = clamp(y, bounds.y + 4.0 * s, max(bounds.w - 4.0 * s - sz.y, bounds.y + 4.0 * s));
    float4 r = float4(x, y, x + sz.x, y + sz.y);
    dlRect(ilInset(r, -2.0), IL_FIELD, 0.55, IL_RADIUS * s + 2.0);
    dlRectEdged(r, IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    return r;
}
#endif

#endif
