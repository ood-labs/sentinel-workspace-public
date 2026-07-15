#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float3 color = theme.background;
    suiComposite(color, 0.010.xxx, suiGridPx(c, 24.0, 0.8));

    float4 shell = float4(0.029, 0.044, 0.971, 0.956);
    suiPanel(color, c, theme, shell, false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(shell.x, shell.y, shell.z, 0.137)));
    suiComposite(color, theme.text, suiFillRect(c, float4(shell.x, shell.y, shell.x + 0.0042, 0.137)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.054, 0.074), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.075, 0.166), suiSectionStyle(), UI_LABEL_CONTROLS));

    suiSlider(color, c, theme, UI_RECT_SLIDER, suiInteraction(UI_INDEX_SLIDER), slider_value);
    suiButton(color, c, theme, UI_RECT_PULSE, suiInteraction(UI_INDEX_PULSE), false);
    bool toggleState = toggle_value != 0;
    suiButton(color, c, theme, UI_RECT_TOGGLE, suiInteraction(UI_INDEX_TOGGLE), toggleState);
    float4 toggleThumb = suiToggleThumb(c, theme, UI_RECT_TOGGLE, (float)toggle_value);
    suiComposite(color, toggleThumb.rgb, toggleThumb.a);
    suiXYPad(color, c, theme, UI_RECT_PAD, suiInteraction(UI_INDEX_PAD), pad);

    SuiTextStyle labelStyle = suiBodyStyle();
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_SLIDER.x, 0.200), labelStyle, UI_LABEL_CONTROL_SLIDER));
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_PULSE.x, 0.200), labelStyle, UI_LABEL_CONTROL_PULSE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_TOGGLE.x, 0.200), labelStyle, UI_LABEL_CONTROL_TOGGLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_PAD.x, 0.400), labelStyle, UI_LABEL_CONTROL_PAD));
    suiComposite(color, theme.text, suiInteger(c, float2(0.408, 0.200), labelStyle, (int)round(slider_value * 100.0), 3));

    suiComposite(color, theme.muted, suiLabelText(c, float2(0.075, 0.854), labelStyle, UI_LABEL_LAYOUT));
    SuiLayout row = suiLayout(float4(0.075, 0.885, 0.923, 0.928), SUI_LAYOUT_ROW, 0.018);
    float4 idleRect = suiLayoutNext(row, 0.165);
    float4 activeRect = suiLayoutNext(row, 0.165);
    float4 selectedRect = suiLayoutNext(row, 0.165);
    float4 disabledRect = suiLayoutNext(row, 0.255);
    suiStatus(color, c, theme, idleRect, 0.18);
    suiStatus(color, c, theme, activeRect, slider_value);
    suiButton(color, c, theme, selectedRect, suiInteractionNone(), true);
    suiControlFrame(color, c, theme, disabledRect);
    suiComposite(color, theme.muted * 0.55, suiFillRect(c, suiControlInterior(c, disabledRect)));

    suiComposite(color, theme.text, suiLabelText(c, idleRect.xy + float2(0.012, 0.012), labelStyle, UI_LABEL_IDLE));
    suiComposite(color, theme.text, suiLabelText(c, activeRect.xy + float2(0.012, 0.012), labelStyle, UI_LABEL_ACTIVE));
    suiComposite(color, theme.background, suiLabelText(c, selectedRect.xy + float2(0.012, 0.012), labelStyle, UI_LABEL_SELECTED));
    suiComposite(color, theme.muted, suiLabelText(c, disabledRect.xy + float2(0.012, 0.012), labelStyle, UI_LABEL_DISABLED));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
