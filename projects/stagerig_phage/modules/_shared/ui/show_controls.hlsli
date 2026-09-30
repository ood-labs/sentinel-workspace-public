// show_controls.hlsli - the show control widget look for Module panels.
//
// Draws pads, faders, knobs, meters, section headers and text from
// `_ViewportControlState` (t126), `_PanelLabels` (t124) and the `_PanelFont`
// ASCII distance atlas (t125), matching the ImGui widget library in
// src/ui/widgets/ShowWidgets.cpp so a Module desk and a Script desk read as
// one family. Every function works in output pixels and composites over an
// inout color, so compute and pixel shaders share it.
//
// Include after the generated prelude of a Module that declares
// viewport.controls:
//     #include "../_shared/ui/show_controls.hlsli"
#ifndef SHOW_CONTROLS_HLSLI
#define SHOW_CONTROLS_HLSLI

#ifndef SENTINEL_PANEL_TEXT
#error show_controls.hlsli needs a Module with viewport.controls
#endif

// Palette: ShowPalette.h values.
static const float3 SC_SURFACE_BASE = float3(12, 12, 13) / 255.0;
static const float3 SC_SURFACE_FRAME = float3(28, 28, 30) / 255.0;
static const float3 SC_SURFACE_RAISED = float3(38, 38, 41) / 255.0;
static const float3 SC_SURFACE_BORDER = float3(52, 52, 56) / 255.0;
static const float3 SC_SURFACE_HOVER = float3(64, 60, 62) / 255.0;
static const float3 SC_TEXT_PRIMARY = float3(230, 227, 222) / 255.0;
static const float3 SC_TEXT_MUTED = float3(128, 126, 124) / 255.0;
static const float3 SC_TEXT_ON_LIT = float3(18, 16, 16) / 255.0;
static const float3 SC_ACCENT = float3(179, 64, 64) / 255.0;
static const float3 SC_ACCENT_HOVERED = float3(204, 82, 82) / 255.0;
static const float3 SC_ROLE_NEUTRAL = float3(158, 158, 168) / 255.0;
static const float3 SC_ROLE_GO = float3(72, 184, 108) / 255.0;
static const float3 SC_ROLE_KILL = float3(222, 62, 56) / 255.0;
static const float3 SC_ROLE_WARN = float3(242, 158, 46) / 255.0;
static const float3 SC_ROLE_FREEZE = float3(52, 158, 200) / 255.0;
static const float3 SC_ROLE_LINK = float3(78, 140, 242) / 255.0;

// Pad states (ViewportControlState.state).
static const uint SC_EMPTY = 0;
static const uint SC_LOADED = 1;
static const uint SC_ACTIVE = 2;
static const uint SC_SELECTED = 3;
static const uint SC_FADING = 4;

static const float SC_ROUNDING = 4.0;

// ---------------------------------------------------------------- geometry

// Signed distance to a rounded box in pixels, negative inside.
float scBox(float2 p, float2 lo, float2 hi, float radius) {
    float2 center = (lo + hi) * 0.5;
    float2 q = abs(p - center) - ((hi - lo) * 0.5 - radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Antialiased coverage of the inside of a distance.
float scFill(float d) { return saturate(0.5 - d); }

// Coverage of a stroke of width w lying just inside the edge.
float scStroke(float d, float w) { return scFill(d) * (1.0 - scFill(d + w)); }

void scOver(inout float3 dst, float3 src, float alpha) { dst = lerp(dst, src, saturate(alpha)); }

float scLuminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float3 scUnpack(uint rgba) {
    return float3(rgba & 255, (rgba >> 8) & 255, (rgba >> 16) & 255) / 255.0;
}

// The role a control draws in: its feedback color when one was set.
float3 scRole(ViewportControlState s, float3 fallback) {
    return s.rgba != 0 ? scUnpack(s.rgba) : fallback;
}

bool scHas(ViewportControlState s, uint flag) { return (s.flags & flag) != 0; }

// ---------------------------------------------------------------- text

static const float SC_FONT_EM = 40.0;
static const float SC_FONT_ADVANCE = 24.0;
static const float SC_FONT_ORIGIN_X = 4.0;
static const float SC_FONT_LINE_TOP = 7.0;
static const float SC_FONT_LINE_HEIGHT = 52.0;

uint scLabelByte(uint control, uint i) {
    return (_PanelLabels[control * PANEL_LABEL_WORDS + i / 4] >> ((i % 4) * 8)) & 255;
}

float scAtlas(int2 texel) { return _PanelFont.Load(int3(texel, 0)); }

// Bilinear distance sample inside one glyph cell (atlas pixels).
float scGlyph(uint ch, float2 cell) {
    if (ch < 33 || ch > 126) return 0.0;
    uint slot = ch - 32;
    int2 base = int2((slot % 16) * 32, (slot / 16) * 64);
    float2 t = clamp(cell, 0.5, float2(31.5, 63.5)) - 0.5;
    int2 i = int2(floor(t));
    float2 f = t - i;
    int2 j = min(i + 1, int2(31, 63));
    float a = lerp(scAtlas(base + i), scAtlas(base + int2(j.x, i.y)), f.x);
    float b = lerp(scAtlas(base + int2(i.x, j.y)), scAtlas(base + j), f.x);
    return lerp(a, b, f.y);
}

// Coverage of `count` bytes of a control's label with the line box's top
// left at `origin`, at an em of `sizePx` pixels.
float scTextAt(float2 p, float2 origin, float sizePx, uint control, uint count) {
    float scale = sizePx / SC_FONT_EM;
    float2 local = (p - origin) / scale;
    if (local.y < 0.0 || local.y >= SC_FONT_LINE_HEIGHT || local.x < 0.0) return 0.0;
    uint i = uint(local.x / SC_FONT_ADVANCE);
    if (i >= count) return 0.0;
    float2 cell = float2(SC_FONT_ORIGIN_X + local.x - i * SC_FONT_ADVANCE, SC_FONT_LINE_TOP + local.y);
    float distance = (scGlyph(scLabelByte(control, i), cell) * 255.0 - 128.0) / 32.0;
    return saturate(distance * scale + 0.5);
}

float scTextWidth(uint count, float sizePx) { return count * SC_FONT_ADVANCE * sizePx / SC_FONT_EM; }

// A control's label centered in a box (left aligned with padding when it
// overflows) and clipped to it. align: 0 center, 1 left, 2 right.
float scLabel(float2 p, float2 lo, float2 hi, uint control, float sizePx, uint align) {
    if (any(p < lo) || any(p > hi)) return 0.0;
    uint count = _ViewportControlState[control].label;
    float width = scTextWidth(count, sizePx);
    float pad = 4.0;
    float x = (lo.x + hi.x - width) * 0.5;
    if (align == 1 || width > hi.x - lo.x - 2.0 * pad) x = lo.x + pad;
    else if (align == 2) x = hi.x - pad - width;
    float lineHeight = SC_FONT_LINE_HEIGHT * sizePx / SC_FONT_EM;
    float y = (lo.y + hi.y - lineHeight) * 0.5;
    return scTextAt(p, float2(x, y), sizePx, control, count);
}

// ---------------------------------------------------------------- controls

// A show pad: empty, loaded, active (role tint, 2 px role border, corner
// pip), selected (accent ring), fading (role fill to `fade`), held (solid
// role). `idleRole` true tints a loaded pad's border with its role, which
// reads kill and warn pads at rest.
void scPad(inout float3 color, float2 p, float2 lo, float2 hi, uint control, float3 fallbackRole,
           float textPx, bool idleRole) {
    float d = scBox(p, lo, hi, SC_ROUNDING);
    if (d > 3.0) return;
    ViewportControlState s = _ViewportControlState[control];
    float3 role = scRole(s, fallbackRole);
    bool hovered = scHas(s, VIEWPORT_CONTROL_HOVER);
    bool held = scHas(s, VIEWPORT_CONTROL_HELD);
    float3 text = SC_TEXT_PRIMARY;
    float inside = scFill(d);
    if (s.state == SC_EMPTY) {
        scOver(color, hovered ? SC_SURFACE_FRAME : SC_SURFACE_BASE, inside);
        float dash = step(fmod(p.x + p.y, 6.0), 3.0);
        scOver(color, SC_SURFACE_BORDER, scStroke(d, 1.0) * dash);
        text = SC_TEXT_MUTED;
    } else if (s.state == SC_ACTIVE) {
        scOver(color, SC_SURFACE_RAISED, inside);
        scOver(color, role, inside * (hovered ? 0.30 : 0.22));
        scOver(color, role, scStroke(d + 1.0, 2.0));
    } else {
        scOver(color, hovered ? SC_SURFACE_HOVER : SC_SURFACE_RAISED, inside);
        scOver(color, idleRole ? role : SC_SURFACE_BORDER, scStroke(d, 1.0) * (idleRole ? 0.75 : 1.0));
    }
    if (s.state == SC_FADING) {
        float edge = lerp(lo.x, hi.x, saturate(s.fade));
        scOver(color, role, inside * 0.35 * saturate(edge - p.x + 0.5));
        scOver(color, role, scStroke(d, 1.0) * 0.6);
    }
    if (s.state == SC_SELECTED) scOver(color, SC_ACCENT_HOVERED, scStroke(d - 1.0, 2.0));
    if (held) {
        scOver(color, role, inside);
        text = scLuminance(role) > 0.55 ? SC_TEXT_ON_LIT : SC_TEXT_PRIMARY;
    }
    if (s.state == SC_ACTIVE && !held) {
        float pip = length(p - float2(hi.x - 6.0, lo.y + 6.0)) - 3.0;
        scOver(color, role, scFill(pip));
    }
    if (idleRole && s.state == SC_LOADED && !held) text = lerp(SC_TEXT_PRIMARY, role, 0.55);
    scOver(color, text, scLabel(p, lo + 1.0, hi - 1.0, control, textPx, 0));
}

// A vertical fader over the control rect: framed track, ticks, a role fill
// from the bottom to the value and a cap centered on the value, clamped
// inside the track. The value maps over the full rect height, as the
// viewport router maps the pointer.
void scFader(inout float3 color, float2 p, float2 lo, float2 hi, uint control, float3 fallbackRole) {
    float d = scBox(p, lo, hi, SC_ROUNDING);
    if (d > 3.0) return;
    ViewportControlState s = _ViewportControlState[control];
    float3 role = scRole(s, fallbackRole);
    bool engaged = scHas(s, VIEWPORT_CONTROL_ACTIVE) || scHas(s, VIEWPORT_CONTROL_HOVER);
    scOver(color, SC_SURFACE_FRAME, scFill(d));
    scOver(color, SC_SURFACE_BORDER, scStroke(d, 1.0));
    float height = hi.y - lo.y;
    for (uint tick = 0; tick <= 10; ++tick) {
        float y = hi.y - 12.0 - tick * (height - 24.0) / 10.0;
        float tickLength = (tick == 0 || tick == 5 || tick == 10) ? 7.0 : 4.0;
        float tickLine = scFill(abs(p.y - y) - 0.5) * step(lo.x + 3.0, p.x) * step(p.x, lo.x + 3.0 + tickLength);
        scOver(color, SC_SURFACE_BORDER, tickLine);
    }
    float cx = (lo.x + hi.x) * 0.5;
    float valueY = hi.y - saturate(s.value) * height;
    float slot = scBox(p, float2(cx - 2.0, lo.y + 12.0), float2(cx + 2.0, hi.y - 12.0), 2.0);
    scOver(color, SC_SURFACE_BASE, scFill(slot));
    float fill = scBox(p, float2(cx - 2.0, max(valueY, lo.y + 12.0)), float2(cx + 2.0, hi.y - 12.0), 2.0);
    scOver(color, role, scFill(fill));
    float capY = clamp(valueY, lo.y + 10.0, hi.y - 10.0);
    float2 capLo = float2(lo.x + 4.0, capY - 10.0), capHi = float2(hi.x - 4.0, capY + 10.0);
    scOver(color, float3(0, 0, 0), 0.47 * scFill(scBox(p, capLo + float2(1, 2), capHi + float2(1, 2), 3.0)));
    float cap = scBox(p, capLo, capHi, 3.0);
    scOver(color, scHas(s, VIEWPORT_CONTROL_ACTIVE) ? SC_SURFACE_HOVER : SC_SURFACE_RAISED, scFill(cap));
    scOver(color, engaged ? role : SC_SURFACE_BORDER, scStroke(cap, 1.0));
    float grip = scBox(p, float2(capLo.x + 4.0, capY - 0.75), float2(capHi.x - 4.0, capY + 0.75), 0.5);
    scOver(color, SC_TEXT_PRIMARY, scFill(grip));
}

// A knob: a 270 degree track ring with a role arc to the value and a
// pointer line, centered in the rect.
void scKnob(inout float3 color, float2 p, float2 lo, float2 hi, uint control, float3 fallbackRole) {
    ViewportControlState s = _ViewportControlState[control];
    float3 role = scRole(s, fallbackRole);
    float2 center = (lo + hi) * 0.5;
    float radius = min(hi.x - lo.x, hi.y - lo.y) * 0.5 - 3.0;
    float2 v = p - center;
    float r = length(v);
    if (r > radius + 2.0) return;
    // Angle measured clockwise from the lower left end of the sweep, 0..1.
    float angle = atan2(v.x, -v.y);                 // 0 at the top, clockwise positive
    float sweep = (angle + 0.75 * 3.14159265) / (1.5 * 3.14159265);
    float ring = scFill(abs(r - radius * 0.82) - radius * 0.09);
    bool onSweep = sweep >= 0.0 && sweep <= 1.0;
    scOver(color, SC_SURFACE_FRAME, scFill(r - radius * 0.62));
    scOver(color, SC_SURFACE_BORDER, scStroke(r - radius * 0.62, 1.0));
    if (onSweep) scOver(color, sweep <= saturate(s.value) ? role : SC_SURFACE_RAISED, ring);
    float pointerAngle = (saturate(s.value) * 1.5 - 0.75) * 3.14159265;
    float2 dir = float2(sin(pointerAngle), -cos(pointerAngle));
    float along = dot(v, dir);
    float across = abs(dot(v, float2(-dir.y, dir.x)));
    if (along > radius * 0.15 && along < radius * 0.58) scOver(color, SC_TEXT_PRIMARY, scFill(across - 1.0));
}

// A vertical segmented meter: value is the level, value2 the peak hold.
// Segments run go to warn (above 0.7) to kill (above 0.9).
void scMeter(inout float3 color, float2 p, float2 lo, float2 hi, uint control) {
    if (any(p < lo) || any(p > hi)) return;
    ViewportControlState s = _ViewportControlState[control];
    float height = hi.y - lo.y;
    float t = (hi.y - p.y) / height;
    float segments = max(8.0, floor(height / 6.0));
    float segment = floor(t * segments);
    float gap = step(0.25, frac(t * segments));
    float level = (segment + 0.5) / segments;
    float3 zone = level > 0.9 ? SC_ROLE_KILL : level > 0.7 ? SC_ROLE_WARN : SC_ROLE_GO;
    float3 unlit = lerp(SC_SURFACE_FRAME, zone, 0.12);
    scOver(color, level <= saturate(s.value) ? zone : unlit, gap);
    float peak = saturate(s.value2);
    if (peak > 0.0 && abs(t - peak) * height < 1.5) scOver(color, SC_TEXT_PRIMARY, 1.0);
}

// A section header: accent tick, the control's label and a divider.
void scHeader(inout float3 color, float2 p, float2 lo, float2 hi, uint control, float textPx) {
    if (any(p < lo) || any(p > hi)) return;
    float tick = scBox(p, float2(lo.x, lo.y + 3.0), float2(lo.x + 3.0, hi.y - 5.0), 0.5);
    scOver(color, SC_ACCENT, scFill(tick));
    scOver(color, SC_TEXT_PRIMARY, scLabel(p, float2(lo.x + 8.0, lo.y), float2(hi.x, hi.y - 2.0), control, textPx, 1));
    scOver(color, SC_SURFACE_BORDER, scFill(abs(p.y - (hi.y - 0.5)) - 0.5));
}

// A numeric or text readout: the control's label in a role color.
void scReadout(inout float3 color, float2 p, float2 lo, float2 hi, uint control, float3 role, float textPx,
               uint align) {
    scOver(color, role, scLabel(p, lo, hi, control, textPx, align));
}

#endif // SHOW_CONTROLS_HLSLI
