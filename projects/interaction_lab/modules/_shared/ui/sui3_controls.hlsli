#ifndef SENTINEL_SUI3_CONTROLS_HLSLI
#define SENTINEL_SUI3_CONTROLS_HLSLI

// Control surfaces, v3. Pixel space throughout.
//
// TWO RULES, both enforced by the shape of these functions rather than by
// discipline:
//
//  1. NO CONTROL TAKES AN INTERACTION STATE. There is no hovered/down argument
//     anywhere in this header, so no control can change appearance on rollover.
//     An instrument reads the same whether or
//     not a pointer happens to be over it.
//  2. EVERY CONTROL RENDERS ITS OWN LIVE VALUE. A control that cannot tell you
//     what it is set to is not an instrument. Where a control is wide enough to
//     carry digits it draws them itself. Where it is not -- a 20px meter in a
//     bank of six -- it renders the value POSITIONALLY (fill extent plus a
//     peak-hold hairline) and the CALLER owes the bank one printed number.
//
// State is carried by STRUCTURE -- an underline, a reticle, a filled rail --
// never by tinting a control's face.

#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "../_shared/ui/sui3_theme.hlsli"

// Inset well with hairline frame and corner brackets. The standard container.
float3 sui3Well(float2 P, float4 r, Sui3Theme t) {
    float3 c = t.well * sui3RectIn(P, r);
    c += t.rule * sui3Frame(P, r);
    c += t.mid * sui3Brackets(P, r, 14.0) * 0.62;
    return c;
}

// XY pad. `val` is the HOST PARAMETER, unmodified -- the same number the
// Properties row shows, the readout prints, and the node publishes. See the
// Y-DIRECTION CONTRACT in sui3_core.hlsli. The manifest rect for a pad is a
// plain bounding box and is normalized here before anything draws with it, so
// every helper below can assume r.y is the top edge.
float3 sui3Pad(float2 P, float4 r, float2 val, Sui3Theme t) {
    r = sui3PadRect(r);
    float3 c = t.well * sui3RectIn(P, r);
    c += t.rule * 0.20 * sui3Graticule(P, r, float2(4.0, 4.0));

    float2 mid = (r.xy + r.zw) * 0.5;
    c += t.rule * 0.32 * sui3HairAt(P.x, mid.x) * sui3RectIn(P, r);
    c += t.rule * 0.32 * sui3HairAt(P.y, mid.y) * sui3RectIn(P, r);

    float2 at = sui3PadPoint(r, val);

    c += t.ink    * sui3Reticle(P, at, 5.0, 24.0) * 0.85;
    c += t.accent * sui3Aa(abs(length(P - at) - 8.5), 1.2) * 0.95;
    c += t.mid    * 0.18 * sui3Ring(P, at, 17.0, 1.0);
    c += t.ink    * sui3Disc(P, at, 1.6) * 0.9;

    c += t.accent * sui3EdgeReadout(P, r, at, 5.0) * 0.9;
    c += t.dim    * 0.5 * sui3Ticks(P, r, 16.0, 3.0, 0);
    c += t.dim    * 0.5 * sui3Ticks(P, r, 10.0, 3.0, 1);

    c += t.rule * sui3Frame(P, r);
    c += t.mid  * sui3Brackets(P, r, 14.0) * 0.62;
    return c;
}

// Horizontal measured rail. Not a filled trough: a hairline scale, a filled
// extent to the current value, and the value printed at the right.
float3 sui3Rail(float2 P, float4 r, float value, Sui3Theme t) {
    float v = saturate(value);
    float3 c = t.well * sui3RectIn(P, r);

    float4 inner = float4(r.x + 2.0, r.y + 2.0, r.z - 2.0, r.w - 2.0);
    float xv = lerp(inner.x, inner.z, v);

    // filled extent, dim; the head, ink; the value, accent
    c += t.mid * 0.28 * sui3RectIn(P, float4(inner.x, inner.y, xv, inner.w));
    c += t.ink * sui3HairAt(P.x, xv) * sui3RectIn(P, inner);
    c += t.dim * 0.55 * sui3Ticks(P, r, 10.0, 4.0, 0);

    c += t.rule * sui3Frame(P, r);
    return c;
}

// Toggle. UNDERLINE when on, never fill. `sui_controls.hlsli:27` filled the
// face with the accent on select, which is the widget grammar this replaces.
float3 sui3Toggle(float2 P, float4 r, bool on, Sui3Theme t) {
    float3 c = t.well * sui3RectIn(P, r);
    c += (on ? t.accent : t.rule) * sui3Frame(P, r);
    c += (on ? t.accent : t.mid * 0.5) * sui3Brackets(P, r, 10.0);
    if (on) {
        c += t.accent * sui3RectIn(P, r) * step(r.w - 3.0, P.y) * 0.9;
    }
    return c;
}

// One cell of a button bank. Same underline-not-fill rule.
float3 sui3BankCell(float2 P, float4 r, bool active, Sui3Theme t) {
    float3 c = (active ? t.well * 1.15 : t.well) * sui3RectIn(P, r);
    c += (active ? t.accent * 0.85 : t.rule) * sui3Frame(P, r);
    c += (active ? t.accent : t.mid * 0.72) * sui3Brackets(P, r, 12.0);
    if (active) c += t.accent * sui3RectIn(P, r) * step(r.w - 3.0, P.y) * 0.9;
    return c;
}

// Vertical bar meter with a peak-hold hairline.
float3 sui3Meter(float2 P, float4 r, float value, float peak, Sui3Theme t) {
    float v = saturate(value);
    float3 c = t.well * sui3RectIn(P, r);
    float yv = lerp(r.w, r.y, v);
    c += t.mid * 0.45 * sui3RectIn(P, float4(r.x, yv, r.z, r.w));
    c += t.ink * sui3HairAt(P.y, yv) * sui3RectIn(P, r);
    float yp = lerp(r.w, r.y, saturate(peak));
    c += t.accent * sui3HairAt(P.y, yp) * sui3RectIn(P, r) * 0.9;
    c += t.rule * sui3Frame(P, r);
    return c;
}

// Distribution bars from a caller-supplied sampling function is not possible in
// HLSL without templates, so callers draw bars with this helper per bar.
float3 sui3Bar(float2 P, float4 slot, float norm, bool established, Sui3Theme t) {
    float h = saturate(norm);
    float yv = lerp(slot.w, slot.y, h);
    float3 c = (established ? t.accent : t.mid) * 0.8
             * sui3RectIn(P, float4(slot.x, yv, slot.z, slot.w));
    return c;
}

// Section rule with a title, the standard band separator.
float3 sui3Rule(float2 P, float2 R, float y, float insetPx, Sui3Theme t) {
    return t.rule * sui3HairAt(P.y, y) * step(insetPx, P.x) * step(P.x, R.x - insetPx);
}

#endif
