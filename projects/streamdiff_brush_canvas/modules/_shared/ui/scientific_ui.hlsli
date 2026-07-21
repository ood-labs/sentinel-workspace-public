#ifndef SENTINEL_SCIENTIFIC_UI_HLSLI
#define SENTINEL_SCIENTIFIC_UI_HLSLI

// Deprecated v1 adapter. New modules should include sui_v2.hlsli and use
// normalized rectangles. These aliases preserve existing authored shaders
// while inheriting antialiased coverage and the monochrome v2 theme.
#include "../_shared/ui/sui_v2.hlsli"

static const float2 SUI_LEGACY_SIZE = float2(960.0, 540.0);

static const float3 SUI_BG = float3(0.004, 0.004, 0.005);
static const float3 SUI_PANEL = float3(0.014, 0.014, 0.016);
static const float3 SUI_PANEL_HI = float3(0.032, 0.032, 0.036);
static const float3 SUI_TEXT = float3(0.94, 0.94, 0.95);
static const float3 SUI_MUTED = float3(0.40, 0.40, 0.43);
static const float3 SUI_BORDER = float3(0.27, 0.27, 0.30);
static const float3 SUI_CYAN = float3(0.72, 0.72, 0.75);
static const float3 SUI_BLUE = float3(0.70, 0.70, 0.73);
static const float3 SUI_AMBER = float3(0.82, 0.82, 0.84);
static const float3 SUI_RED = float3(0.58, 0.58, 0.61);
static const float3 SUI_AXIS_X = float3(1.00, 0.25, 0.30);
static const float3 SUI_AXIS_Y = float3(0.30, 0.95, 0.38);
static const float3 SUI_AXIS_Z = float3(0.24, 0.56, 1.00);

float suiLegacyAa(float distancePx) { return 1.0 - smoothstep(-0.65, 0.65, distancePx); }

float suiRect(float2 p, float4 rect) {
    float2 center = (rect.xy + rect.zw) * 0.5;
    float2 halfSize = max((rect.zw - rect.xy) * 0.5, 0.0);
    float2 q = abs(p - center) - halfSize;
    return suiLegacyAa(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));
}

float suiRectBorder(float2 p, float4 rect, float width) {
    float outer = suiRect(p, rect);
    float inner = suiRect(p, float4(rect.xy + width, rect.zw - width));
    return saturate(outer - inner);
}

float suiRoundBox(float2 p, float2 center, float2 halfSize, float radius) {
    float2 q = abs(p - center) - halfSize + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

float suiLine(float2 p, float2 a, float2 b, float width) {
    float2 ba = b - a;
    float h = saturate(dot(p - a, ba) / max(dot(ba, ba), 1e-6));
    return suiLegacyAa(length(p - (a + ba * h)) - width * 0.5);
}

float suiRing(float2 p, float2 center, float radius, float width) {
    return suiLegacyAa(abs(length(p - center) - radius) - width * 0.5);
}

float suiGrid(float2 p, float spacing, float width) {
    float2 d = abs(frac(p / spacing + 0.5) - 0.5) * spacing;
    return suiLegacyAa(min(d.x, d.y) - width * 0.5);
}

float3 suiControlOutline() { return SUI_BORDER; }

float suiRegularGlyphAt(float2 local, int code) {
    int col = (int)floor(local.x), row = (int)floor(local.y);
    return suiGlyphBit(code, col, row);
}

float suiGlyphWeight(float2 p, float2 anchor, float scale, int code, float weight) {
    return suiGlyphCoveragePx(p, anchor, suiTextStyle(scale, weight), code);
}

float suiGlyph(float2 p, float2 anchor, float scale, int code, int emphasis) {
    return suiGlyphWeight(p, anchor, scale, code, emphasis > 0 ? 0.28 : 0.0);
}

float suiDigit(float2 p, float2 anchor, float scale, int value, int digits) {
    float coverage = 0.0;
    int v = max(value, 0);
    [loop] for (int i = 0; i < digits; ++i) {
        int place = 1;
        [loop] for (int k = 0; k < digits - 1 - i; ++k) place *= 10;
        int digit = (v / place) % 10;
        coverage = max(coverage, suiGlyph(p, anchor + float2((float)i * 7.0 * scale, 0.0), scale, 48 + digit, 0));
    }
    return coverage;
}

float suiButtonState(float2 p, float4 rect, bool pressed, out float3 fill) {
    float inside = suiRect(p, rect);
    float4 interior = float4(rect.xy + 3.0, rect.zw - 3.0);
    fill = SUI_PANEL_HI;
    fill = lerp(fill, pressed ? SUI_TEXT : SUI_PANEL_HI, suiRect(p, interior));
    fill = lerp(fill, SUI_BORDER, suiRectBorder(p, rect, 2.0));
    return inside;
}

float suiButton(float2 p, float4 rect, uint controlIndex, out float3 fill) {
    return suiButtonState(p, rect, false, fill);
}

float suiSlider(float2 p, float4 rect, float value, uint controlIndex, out float3 fill) {
    float inside = suiRect(p, rect);
    float4 interior = float4(rect.xy + 3.0, rect.zw - 3.0);
    float4 amount = interior;
    amount.z = lerp(interior.x, interior.z, saturate(value));
    fill = SUI_PANEL_HI;
    fill = lerp(fill, SUI_MUTED, suiRect(p, amount));
    fill = lerp(fill, SUI_BORDER, suiRectBorder(p, rect, 2.0));
    return inside;
}

float suiToggle(float2 p, float4 rect, bool enabled, uint controlIndex, out float3 fill) {
    return suiButtonState(p, rect, enabled, fill);
}

float suiPad(float2 p, float4 rect, float2 value, uint controlIndex, out float3 fill, out float marker) {
    float inside = suiRect(p, rect);
    fill = lerp(SUI_PANEL, SUI_BORDER, suiRectBorder(p, rect, 2.0));
    float2 m = lerp(rect.xy + 3.0, rect.zw - 3.0, saturate(value));
    marker = suiLegacyAa(length(p - m) - 6.0);
    return inside;
}

#endif
