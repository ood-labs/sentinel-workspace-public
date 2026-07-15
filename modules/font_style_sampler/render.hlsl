#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

uint rowLabel(uint row) {
    if (row == 0u) return UI_LABEL_REGULAR;
    if (row == 1u) return UI_LABEL_LIGHT;
    if (row == 2u) return UI_LABEL_CLEAN;
    return UI_LABEL_FULL;
}

float rowWeight(uint row) {
    if (row == 0u) return 0.0;
    if (row == 1u) return 0.14;
    if (row == 2u) return 0.28;
    return 1.0;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float3 color = theme.background;
    suiComposite(color, 0.009.xxx, suiGridPx(c, 24.0, 0.8));
    suiPanel(color, c, theme, float4(0.029, 0.044, 0.971, 0.956), false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.029, 0.044, 0.971, 0.139)));
    suiComposite(color, theme.text, suiFillRect(c, float4(0.029, 0.044, 0.0332, 0.139)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.054, 0.074), suiTextStyle(2.0, 0.28), UI_LABEL_TITLE));

    float rowY[4] = { 0.196, 0.363, 0.530, 0.697 };
    [unroll] for (uint row = 0u; row < 4u; ++row) {
        float4 card = float4(0.054, rowY[row], 0.946, rowY[row] + 0.130);
        bool selected = (uint)selected_style == row;
        suiPanel(color, c, theme, card, selected);
        suiComposite(color, selected ? theme.text : theme.muted,
            suiLabelText(c, card.xy + float2(0.018, 0.047), suiTextStyle(1.0, 0.0), rowLabel(row)));
        suiComposite(color, selected ? theme.text : theme.accent,
            suiLabelText(c, card.xy + float2(0.260, 0.031), suiTextStyle(4.0, rowWeight(row)), UI_LABEL_SPECIMEN));
    }

    suiSlider(color, c, theme, UI_RECT_WEIGHT, suiInteraction(UI_INDEX_WEIGHT), custom_weight);
    suiComposite(color, theme.text,
        suiLabelText(c, float2(0.073, 0.872), suiTextStyle(3.0, custom_weight), UI_LABEL_SPECIMEN));
    suiComposite(color, theme.text,
        suiInteger(c, float2(0.880, 0.884), suiTextStyle(1.0, 0.0), (int)round(custom_weight * 100.0), 3));
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
