#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float generatedText(SuiContext c, float2 anchor, SuiTextStyle style, uint labelId) {
    float coverage = 0.0;
    float advance = 8.0 * style.scalePx + style.trackingPx;
    [loop] for (int i = 0; i < uiLabelLength(labelId); ++i) {
        coverage = max(coverage, suiGlyph(c, anchor + float2(i * advance, 0.0) * c.invResolution, style, uiLabelCode(labelId, i)));
    }
    return coverage;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float3 color = theme.background;
    suiPanel(color, c, theme, float4(0.04, 0.06, 0.96, 0.94), false);
    suiComposite(color, theme.text, generatedText(c, float2(0.08, 0.12), suiTitleStyle(), UI_LABEL_TITLE));
    suiSlider(color, c, theme, UI_RECT_AMOUNT, suiInteraction(UI_INDEX_AMOUNT), amount);
    suiButton(color, c, theme, UI_RECT_APPLY, suiInteraction(UI_INDEX_APPLY), false);
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
