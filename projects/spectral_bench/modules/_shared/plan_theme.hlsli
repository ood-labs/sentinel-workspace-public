// plan_theme.hlsli — the shared instrument palette for AUTHORED PLAN / EDITOR CANVASES.
//
// Vendorable generic infrastructure: copy this file into the owning project's own
// `modules/_shared/` and include it from there. Never include it across project boundaries.
//
// WHAT THIS IS FOR. A plan authority's canvas is an INSTRUMENT, not a picture. Its job is to be
// read — where things are, which are selected, which are hand-edited, and whether anything is
// wrong. A saturated diagram competes with the program image it is supposed to explain, and
// every hue spent on chrome is a hue unavailable for meaning.
//
// THE RULE: MOSTLY MONOCHROME, HUE ONLY WHERE IT CARRIES INFORMATION.
//
// Monochrome, always: the ground, panel fills, hairlines, ticks, grids, frames, captions, and
// any ordinal ramp (kind, rank, weight) that a legend can carry.
//
// Hue is permitted for a small number of things a value alone genuinely cannot say. Four earn it
// in practice; a build should be able to name every one it uses and why:
//
//   1. ACCENT (PT_ACCENT, amber) — RESERVED. The active selection, and an established live
//      reading such as a playhead. Never hover, never decoration, never an idle control.
//   2. ALARM (PT_ALARM, red) — the one state that means the composition is BROKEN. Deliberately
//      not amber so it can never be confused with a selection.
//   3. IDENTITY — a small closed set the viewer must tell apart at a glance and which has no
//      natural order: which of three walls, which of four lanes, which axis. Use PT_ID_* or a
//      similarly muted set. If the set is ordinal or larger than about four, use the value ramp
//      instead.
//   4. REAL COLOUR OF A THING — when the record itself stores a colour that the user chose (a
//      lamp's hue, a material's tint), showing it is information, not decoration. Pass it through
//      ptSampleColour() so it is pulled toward grey and normalized in brightness, or a saturated
//      record will outshine the accent and break rule 1.
//
// Everything else stays grey. Both failure modes are real and both were hit while this was being
// derived: a fully monochrome first pass turned three identical grey curves into a tangle and
// threw away lamp colour the records already held, while the original saturated version made the
// diagram louder than the render.
#ifndef SENTINEL_PLAN_THEME_HLSLI
#define SENTINEL_PLAN_THEME_HLSLI

// Value ladder. Matches interaction_lab's sui3 theme so plan canvases and UI stations read as
// one family. Slightly warm-neutral rather than blue — a blue ground reads as "screen", a
// neutral one reads as "instrument".
#define PT_FIELD  float3(0.0055, 0.0060, 0.0065)   // the near-black ground everything sits on
#define PT_WELL   float3(0.0125, 0.0135, 0.0145)   // lifted ground inside an inset region
#define PT_GRID   float3(0.0520, 0.0545, 0.0510)   // background grids, station lines
#define PT_RULE   float3(0.2200, 0.2250, 0.2150)   // hairline chrome, frames, inactive marks
#define PT_DIM    float3(0.3800, 0.3850, 0.3700)   // secondary type, ticks, limits
#define PT_MID    float3(0.6000, 0.6050, 0.5800)   // plotted data that is not itself a reading
#define PT_INK    float3(0.9000, 0.9050, 0.8800)   // primary type and live geometry

#define PT_ACCENT float3(1.000, 0.420, 0.090)      // RESERVED — selection / live reading
#define PT_ALARM  float3(1.000, 0.250, 0.300)      // RESERVED — broken state

// Muted identity set, for a small closed group the viewer must distinguish. Desaturated on
// purpose: these must never outrank the accent.
#define PT_ID_A   float3(0.400, 0.505, 0.590)
#define PT_ID_B   float3(0.530, 0.455, 0.585)
#define PT_ID_C   float3(0.405, 0.560, 0.495)
#define PT_ID_D   float3(0.590, 0.545, 0.420)

float3 ptId(int i)
{
    int k = ((i % 4) + 4) % 4;
    return (k == 0) ? PT_ID_A : ((k == 1) ? PT_ID_B : ((k == 2) ? PT_ID_C : PT_ID_D));
}

// Ordinal ramp for kind / rank / weight. Use this instead of hue whenever the set is ordered or
// has more than about four members.
float3 ptRamp(float t)
{
    return lerp(PT_RULE * 1.45, PT_INK, saturate(t));
}

// Pass a record's OWN colour through this before drawing it. Keeping the hue says which thing it
// is; flattening the luminance stops a saturated record reading as brighter or dimmer than a
// neutral one when both are equally live, and stops a warm one impersonating the accent.
float3 ptSampleColour(float3 raw)
{
    float l = dot(raw, float3(0.2126, 0.7152, 0.0722));
    float3 c = lerp(l.xxx, raw, 0.40);
    return c * (0.88 / max(dot(c, float3(0.2126, 0.7152, 0.0722)), 1e-3));
}

// The same idea for a LARGE FILLED AREA rather than a small mark.
//
// ptSampleColour normalizes brightness UP so every mark reads as equally live, which is correct
// for a lamp dot and actively wrong for a body fill: applied to big shapes it makes the loud
// ones louder. A fill keeps less of its hue and gets dimmer, never brighter, so a diagram made
// mostly of coloured bodies still reads as an instrument.
float3 ptSampleFill(float3 raw)
{
    float l = dot(raw, float3(0.2126, 0.7152, 0.0722));
    return lerp(l.xxx, raw, 0.30) * 0.72;
}

// An image the canvas is previewing for real (a generated plate, a core, a material chip) is
// DATA, not chrome, so it is not made monochrome — but at full strength it becomes the loudest
// thing in an instrument frame and outranks the readouts. Pull it back with this.
float3 ptInset(float3 rgb)
{
    float l = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    return lerp(l.xxx, rgb, 0.55) * 0.62;
}

#endif
