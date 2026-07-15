
#ifndef SENTINEL_SUI_GENERATED_TEXT_HLSLI
#define SENTINEL_SUI_GENERATED_TEXT_HLSLI

// Include sui_v2.hlsli and the module's _ui.generated.hlsli before this file.
float suiLabelText(SuiContext c, float2 anchorUv, SuiTextStyle style, uint labelId) {
    float coverage = 0.0;
    float advance = 8.0 * style.scalePx + style.trackingPx;
    [loop] for (int i = 0; i < uiLabelLength(labelId); ++i) {
        float2 offsetUv = float2((float)i * advance, 0.0) * c.invResolution;
        coverage = max(coverage, suiGlyph(c, anchorUv + offsetUv, style, uiLabelCode(labelId, i)));
    }
    return coverage;
}

#endif

