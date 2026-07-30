#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct SwitcherState
{
    float selected;
    float elapsed;
    float auto_latch;
    float one_latch;
    float two_latch;
    float three_latch;
    float cycle_pulse;
    float reserved;
};

StructuredBuffer<SwitcherState> Switcher : register(t1);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y)
        return;

    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    theme.accent = float3(1.0, 0.39, 0.015);
    SwitcherState state = Switcher[0];
    int selected = clamp((int)round(state.selected), 0, 2);

    float3 color = float3(0.0, 0.0, 0.0);
    float4 header = float4(0.0, 0.0, 1.0, 0.13);
    suiComposite(color, theme.panel, suiFillRect(c, header));
    suiComposite(color, theme.border, suiLinePx(c, float2(0.0, header.w), float2(1.0, header.w), 1.0));

    float4 container = float4(0.0, header.w, 1.0, 1.0);
    uint inputWidth = 1u;
    uint inputHeight = 1u;
    _Tex0.GetDimensions(inputWidth, inputHeight);
    float inputAspect = (float)inputWidth / max((float)inputHeight, 1.0);
    float containerAspect = ((container.z - container.x) * _Resolution.x) /
                            max((container.w - container.y) * _Resolution.y, 1.0);
    float4 stage = container;
    if (containerAspect > inputAspect)
    {
        float fittedWidth = (container.w - container.y) * _Resolution.y * inputAspect / _Resolution.x;
        float centerX = (container.x + container.z) * 0.5;
        stage.x = centerX - fittedWidth * 0.5;
        stage.z = centerX + fittedWidth * 0.5;
    }
    else
    {
        float fittedHeight = (container.z - container.x) * _Resolution.x / inputAspect / _Resolution.y;
        float centerY = (container.y + container.w) * 0.5;
        stage.y = centerY - fittedHeight * 0.5;
        stage.w = centerY + fittedHeight * 0.5;
    }

    float insideStage = step(stage.x, c.uv.x) * step(c.uv.x, stage.z) *
                        step(stage.y, c.uv.y) * step(c.uv.y, stage.w);
    float2 stageUv = saturate((c.uv - stage.xy) / max(stage.zw - stage.xy, 1e-5.xx));
    float3 program = _Tex0.SampleLevel(LinearSampler, stageUv, 0.0).rgb;
    color = lerp(color, program, insideStage);
    suiComposite(color, theme.border, suiStrokeRect(c, stage, 1.0));

    bool autoSelected = auto_mode != 0;
    suiButton(color, c, theme, UI_RECT_AUTO_MODE, suiInteraction(UI_INDEX_AUTO_MODE), autoSelected);
    suiButton(color, c, theme, UI_RECT_SELECT_1, suiInteraction(UI_INDEX_SELECT_1), selected == 0);
    suiButton(color, c, theme, UI_RECT_SELECT_2, suiInteraction(UI_INDEX_SELECT_2), selected == 1);
    suiButton(color, c, theme, UI_RECT_SELECT_3, suiInteraction(UI_INDEX_SELECT_3), selected == 2);

    SuiTextStyle body = suiBodyStyle();
    suiComposite(color, theme.text, suiLabelText(c, float2(0.020, 0.030), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.020, 0.081), body, UI_LABEL_SUBTITLE));
    suiComposite(color, autoSelected ? 0.01.xxx : theme.text,
                 suiLabelText(c, float2(0.574, 0.057), body, UI_LABEL_CONTROL_AUTO_MODE));
    suiComposite(color, selected == 0 ? 0.01.xxx : theme.text,
                 suiLabelText(c, float2(0.733, 0.057), body, UI_LABEL_CONTROL_SELECT_1));
    suiComposite(color, selected == 1 ? 0.01.xxx : theme.text,
                 suiLabelText(c, float2(0.833, 0.057), body, UI_LABEL_CONTROL_SELECT_2));
    suiComposite(color, selected == 2 ? 0.01.xxx : theme.text,
                 suiLabelText(c, float2(0.933, 0.057), body, UI_LABEL_CONTROL_SELECT_3));

    if (autoSelected)
    {
        float progress = saturate(state.elapsed / max(cycle_seconds, 0.25));
        float4 track = float4(0.55, 0.114, 0.98, 0.119);
        suiComposite(color, theme.muted, suiFillRect(c, track));
        float4 fill = track;
        fill.z = lerp(track.x, track.z, progress);
        suiComposite(color, theme.accent, suiFillRect(c, fill));
    }

    float pulse = saturate(state.cycle_pulse);
    suiComposite(color, theme.accent, suiStrokeRect(c, stage, 1.0 + 2.0 * pulse) * pulse);
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
