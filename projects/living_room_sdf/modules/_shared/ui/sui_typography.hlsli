#ifndef SENTINEL_SUI_TYPOGRAPHY_HLSLI
#define SENTINEL_SUI_TYPOGRAPHY_HLSLI

#include "../_shared/fonts/scientifica_ascii.hlsli"

struct SuiTextStyle {
    float scalePx;
    float trackingPx;
    float weight;
};

// Approved Scientific UI role defaults. Keep these named so authored modules
// inherit the tuned system without duplicating typography values.
static const float SUI_TITLE_SCALE_PX = 2.0;
static const float SUI_TITLE_WEIGHT = 0.2;
static const float SUI_TITLE_TRACKING_PX = -2.5;
static const float SUI_SECTION_SCALE_PX = 1.75;
static const float SUI_SECTION_WEIGHT = 0.0;
static const float SUI_SECTION_TRACKING_PX = -2.5;
static const float SUI_BODY_SCALE_PX = 1.5;
static const float SUI_BODY_WEIGHT = 0.0;
static const float SUI_BODY_TRACKING_PX = -2.5;

SuiTextStyle suiTextStyle(float scalePx, float weight) {
    SuiTextStyle s;
    s.scalePx = scalePx;
    s.trackingPx = scalePx;
    s.weight = saturate(weight);
    return s;
}

SuiTextStyle suiTextStyleTracked(float scalePx, float weight, float trackingPx) {
    SuiTextStyle s;
    s.scalePx = scalePx;
    s.trackingPx = trackingPx;
    s.weight = saturate(weight);
    return s;
}

SuiTextStyle suiTitleStyle() {
    return suiTextStyleTracked(SUI_TITLE_SCALE_PX, SUI_TITLE_WEIGHT, SUI_TITLE_TRACKING_PX);
}

SuiTextStyle suiSectionStyle() {
    return suiTextStyleTracked(SUI_SECTION_SCALE_PX, SUI_SECTION_WEIGHT, SUI_SECTION_TRACKING_PX);
}

SuiTextStyle suiBodyStyle() {
    return suiTextStyleTracked(SUI_BODY_SCALE_PX, SUI_BODY_WEIGHT, SUI_BODY_TRACKING_PX);
}

float suiGlyphBit(int code, int col, int row) {
    if (code < SCIENTIFICA_FIRST || code > SCIENTIFICA_LAST || col < 0 || col >= 8 || row < 0 || row >= 11) return 0.0;
    int bits = scientificaRowForFace(0, code, row);
    return (float)((bits >> (7 - col)) & 1);
}

float suiGlyphCoveragePx(float2 pixel, float2 anchorPx, SuiTextStyle style, int code) {
    float scalePx = max(style.scalePx, 1.0);
    float2 local = (pixel - anchorPx) / scalePx - 0.5;
    int2 cell = (int2)floor(local);
    float2 f = frac(local);
    float b00 = suiGlyphBit(code, cell.x, cell.y);
    float b10 = suiGlyphBit(code, cell.x + 1, cell.y);
    float b01 = suiGlyphBit(code, cell.x, cell.y + 1);
    float b11 = suiGlyphBit(code, cell.x + 1, cell.y + 1);
    float filtered = lerp(lerp(b00, b10, f.x), lerp(b01, b11, f.x), f.y);
    float grown = max(filtered, suiGlyphBit(code, cell.x - 1, cell.y) * style.weight);
    return saturate(grown);
}

float suiGlyph(SuiContext c, float2 anchorUv, SuiTextStyle style, int code) {
    return suiGlyphCoveragePx(c.pixel, anchorUv * c.resolution, style, code);
}

float suiInteger(SuiContext c, float2 anchorUv, SuiTextStyle style, int value, int digits) {
    float coverage = 0.0;
    int v = max(value, 0);
    float advance = 6.0 * style.scalePx + style.trackingPx;
    [loop] for (int i = 0; i < digits; ++i) {
        int place = 1;
        [loop] for (int k = 0; k < digits - 1 - i; ++k) place *= 10;
        int digit = (v / place) % 10;
        float2 offsetUv = float2((float)i * advance, 0.0) * c.invResolution;
        coverage = max(coverage, suiGlyph(c, anchorUv + offsetUv, style, 48 + digit));
    }
    return coverage;
}

#endif


