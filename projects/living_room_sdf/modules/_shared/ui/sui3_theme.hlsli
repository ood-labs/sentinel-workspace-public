#ifndef SENTINEL_SUI3_THEME_HLSLI
#define SENTINEL_SUI3_THEME_HLSLI

// Instrument palette, v3.
//
// This struct has NO hover, controlDown, controlHover, panelRaised, or control
// member, and that absence is the point. Accent communicates selection or a
// trusted live value, never rollover state or decorative chrome.
//
// Omitting the members makes the old look unreachable by construction rather
// than by discipline: a shader cannot tint a control by hover state here
// because there is no colour to tint it with.
//
// ACCENT CONTRACT. `accent` is reserved for two things only:
//   1. the active selection
//   2. an established live value -- a reading the instrument stands behind
// It is never used for hover, never for decoration, and never for an idle
// control. A capture showing accent on idle chrome is a defect.

struct Sui3Theme {
    float3 field;    // the near-black ground everything is drawn onto
    float3 well;     // slightly lifted ground inside an inset control
    float3 rule;     // hairline chrome. NAMED `rule`, NOT `line`: `line` is an
                     // HLSL reserved word (geometry-shader primitive type) and
                     // a member called `line` fails with X3000 syntax error.
                     // Same class of trap as AUTOPSIA's `centroid` collision.
    float3 dim;      // secondary type, ticks, captions
    float3 mid;      // plotted data that is not itself a reading
    float3 ink;      // primary type and live geometry
    float3 accent;   // RESERVED - see the accent contract above
};

Sui3Theme sui3Theme(float3 accent) {
    Sui3Theme t;
    t.field  = float3(0.0055, 0.0060, 0.0065);
    t.well   = float3(0.0125, 0.0135, 0.0145);
    t.rule   = float3(0.220, 0.225, 0.215);
    t.dim    = float3(0.380, 0.385, 0.370);
    t.mid    = float3(0.600, 0.605, 0.580);
    t.ink    = float3(0.900, 0.905, 0.880);
    t.accent = accent;
    return t;
}

// Scale every non-accent level by a single exposure control, so a station can
// be dimmed as a unit without touching the accent's reserved meaning.
Sui3Theme sui3ThemeExposed(float3 accent, float exposure) {
    Sui3Theme t = sui3Theme(accent);
    float e = max(exposure, 0.05);
    t.well *= e; t.rule *= e; t.dim *= e; t.mid *= e; t.ink *= e;
    return t;
}

static const float3 SUI3_AMBER = float3(1.00, 0.42, 0.09);

// The ONLY other chroma permitted anywhere in the v3 language. These carry
// directional meaning in a 3D gizmo and are exempt from the monochrome rule for
// that reason alone.
static const float3 SUI3_AXIS_X = float3(1.00, 0.25, 0.30);
static const float3 SUI3_AXIS_Y = float3(0.30, 0.95, 0.38);
static const float3 SUI3_AXIS_Z = float3(0.24, 0.56, 1.00);

#endif
