#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

struct DeskState {
    float focus_x; float focus_y; float rupture_x; float rupture_y;
    float pressure_value; float reindex_value; float strike_value; float phase_value;
};

StructuredBuffer<DeskState> Desk : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float4 fittedStageRect(float2 resolution) {
    float4 container = float4(0.345, 0.075, 0.965, 0.915);
    float2 containerPx = (container.zw - container.xy) * resolution;
    float containerAspect = containerPx.x / max(containerPx.y, 1.0);
    float targetAspect = 16.0 / 9.0;
    float2 stagePx = containerPx;
    if (containerAspect > targetAspect) {
        stagePx.x = stagePx.y * targetAspect;
    } else {
        stagePx.y = stagePx.x / targetAspect;
    }
    float2 stageSize = stagePx / resolution;
    float2 center = (container.xy + container.zw) * 0.5;
    return float4(center - stageSize * 0.5, center + stageSize * 0.5);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    DeskState state = Desk[0];
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float3 color = theme.background;

    suiComposite(color, 0.012.xxx, suiGridPx(c, 24.0, 0.8));
    float4 shell = float4(0.020, 0.025, 0.980, 0.970);
    suiPanel(color, c, theme, shell, false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(shell.x, shell.y, shell.z, 0.115)));
    suiComposite(color, float3(0.93, 0.055, 0.03), suiFillRect(c, float4(shell.x, shell.y, shell.x + 0.0045, 0.115)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.044, 0.057), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.055, 0.145), suiSectionStyle(), UI_LABEL_MACROS));

    suiSlider(color, c, theme, UI_RECT_PHASE, suiInteraction(UI_INDEX_PHASE), state.phase_value);
    suiSlider(color, c, theme, UI_RECT_PRESSURE, suiInteraction(UI_INDEX_PRESSURE), state.pressure_value);
    suiSlider(color, c, theme, UI_RECT_REINDEX, suiInteraction(UI_INDEX_REINDEX), state.reindex_value);
    // The host's momentary parameter can retain its last displayed value after the
    // release edge. The compute lane intentionally publishes a neutral resting
    // lamp; the physical press still drives the authoritative host parameter path.
    suiButton(color, c, theme, UI_RECT_STRIKE, suiInteraction(UI_INDEX_STRIKE), state.strike_value > 0.5);
    suiXYPad(color, c, theme, UI_RECT_FOCUS, suiInteraction(UI_INDEX_FOCUS), float2(state.focus_x, state.focus_y));
    float2 ruptureNorm = float2(state.rupture_x, state.rupture_y) * 0.5 + 0.5;
    suiXYPad(color, c, theme, UI_RECT_RUPTURE, suiInteraction(UI_INDEX_RUPTURE), ruptureNorm);

    SuiTextStyle body = suiBodyStyle();
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_PHASE.x, UI_RECT_PHASE.y - 0.028), body, UI_LABEL_CONTROL_PHASE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_PRESSURE.x, UI_RECT_PRESSURE.y - 0.028), body, UI_LABEL_CONTROL_PRESSURE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_REINDEX.x, UI_RECT_REINDEX.y - 0.028), body, UI_LABEL_CONTROL_REINDEX));
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_STRIKE.x, UI_RECT_STRIKE.y - 0.028), body, UI_LABEL_CONTROL_STRIKE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_FOCUS.x, UI_RECT_FOCUS.y - 0.028), body, UI_LABEL_CONTROL_FOCUS));
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_RUPTURE.x, UI_RECT_RUPTURE.y - 0.028), body, UI_LABEL_CONTROL_RUPTURE));

    float4 stage = fittedStageRect(_Resolution.xy);
    float stageFill = step(stage.x, uv.x) * step(uv.x, stage.z) *
                      step(stage.y, uv.y) * step(uv.y, stage.w);
    float2 stageUv = saturate((uv - stage.xy) / max(stage.zw - stage.xy, 0.0001.xx));
    float3 program = _Tex0.SampleLevel(LinearSampler, stageUv, 0).rgb;
    color = lerp(color, program, stageFill);

    float stageBorder = suiStrokeRect(c, stage, 1.0);
    suiComposite(color, theme.text, stageBorder);
    suiComposite(color, theme.muted, suiLabelText(c, float2(stage.x, max(0.035, stage.y - 0.035)), body, UI_LABEL_PROGRAM));

    float2 stageFocus = lerp(stage.xy, stage.zw, float2(state.focus_x, state.focus_y));
    float2 focusPx = (uv - stageFocus) * _Resolution.xy;
    float focusRing = smoothstep(1.8, 0.0, abs(length(focusPx) - 12.0));
    float focusCross = max(
        smoothstep(1.5, 0.0, abs(focusPx.x)) * step(abs(focusPx.y), 18.0),
        smoothstep(1.5, 0.0, abs(focusPx.y)) * step(abs(focusPx.x), 18.0)
    );
    color = lerp(color, float3(0.96, 0.07, 0.035), (focusRing + focusCross) * stageFill);

    float active = max(max(state.pressure_value, state.reindex_value), state.strike_value);
    float4 statusRect = float4(0.345, 0.930, 0.965, 0.955);
    suiStatus(color, c, theme, statusRect, active);
    suiComposite(color, theme.text, suiLabelText(c, statusRect.xy + float2(0.010, 0.004), body, UI_LABEL_LIVE));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
