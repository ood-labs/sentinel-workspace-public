#ifndef MOTION_CONSOLE_LAYOUT_HLSLI
#define MOTION_CONSOLE_LAYOUT_HLSLI

// Shared layout. The control rects come from _ui.generated.hlsli -- the same
// numbers the HOST hit-tests -- so the drawn control and the clickable region
// cannot disagree. See modules/style_authority/layout.hlsli for the reasoning;
// this module follows the same contract.
//
// The BURST rect is the exception and is defined here, because burst is not a
// host control (see manifest.yaml for why `type: button` is unusable). Both the
// renderer and the events pass read it from this one constant.
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "_ui.generated.hlsli"

float4 mcPx(float4 n, float2 R) { return float4(n.x * R.x, n.y * R.y, n.z * R.x, n.w * R.y); }

// Normalized, matching the drawn burst plate.
static const float4 MC_RECT_BURST = float4(0.700, 0.030, 0.795, 0.075);

// Lane i band, normalized. Four semantic lanes preserved from v1; README.md:20's
// reusable lesson stands and is not relitigated.
//
// Pitch 0.180 with height 0.140 leaves a 0.040 gutter between bands, which is
// what the lane label lives in. At 0.150 tall the gutter was 0.030 -- 10.8px at
// a 360px-tall panel, less than one 11px glyph -- so labels sat on the band
// above them. The stack still ends at 0.830; only the gutter changed.
float4 mcLaneBand(int i) {
    float top = 0.150 + (float)i * 0.180;
    return float4(0.020, top, 0.600, top + 0.140);
}

float4 mcLaneSpeed(int i, float2 R) {
    return mcPx(i == 0 ? UI_RECT_L1_SPEED : i == 1 ? UI_RECT_L2_SPEED
              : i == 2 ? UI_RECT_L3_SPEED : UI_RECT_L4_SPEED, R);
}
float4 mcLaneAmp(int i, float2 R) {
    return mcPx(i == 0 ? UI_RECT_L1_AMP : i == 1 ? UI_RECT_L2_AMP
              : i == 2 ? UI_RECT_L3_AMP : UI_RECT_L4_AMP, R);
}
float4 mcLaneShape(int i, float2 R) {
    return mcPx(i == 0 ? UI_RECT_L1_SHAPE : i == 1 ? UI_RECT_L2_SHAPE
              : i == 2 ? UI_RECT_L3_SHAPE : UI_RECT_L4_SHAPE, R);
}

bool mcHit(float2 p, float4 r) {
    return p.x >= r.x && p.x <= r.z && p.y >= r.y && p.y <= r.w;
}

// A label is a fixed number of PIXELS tall, but the gap it sits in is
// NORMALIZED and therefore shrinks with the panel. At 1920x403 the 0.015 gap
// between the rate rail and the shape bank is 6px, and an 11px label drawn
// there lands on the rail above it. Callers pass the real gap; a label that
// cannot fit is dropped rather than drawn over its neighbour. Dropping the word
// "SHAPE" from a bank whose selected cell is already accented costs far less
// than printing it across another control.
bool mcLabelFits(float gapPx, float sB) { return gapPx >= 12.0 * sB; }

#endif
