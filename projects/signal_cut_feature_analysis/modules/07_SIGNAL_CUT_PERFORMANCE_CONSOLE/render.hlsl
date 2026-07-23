#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    theme.accent = float3(1.0, 0.39, 0.015);
    float3 color = float3(0.0015, 0.0015, 0.0015);
    suiComposite(color, 0.012.xxx, suiGridPx(c, 24.0, 0.75));

    suiPanel(color, c, theme, float4(0.018, 0.028, 0.982, 0.972), false);
    suiComposite(color, theme.text, suiLabelText(c, float2(0.035, 0.063), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.accent, suiFillRect(c, float4(0.035, 0.096, 0.162, 0.101)));

    float4 container = float4(0.035, 0.122, 0.585, 0.902);
    float containerAspect = ((container.z - container.x) * _Resolution.x) /
                            max((container.w - container.y) * _Resolution.y, 1.0);
    float programAspect = 16.0 / 9.0;
    float4 stage = container;
    if (containerAspect > programAspect)
    {
        float fittedWidth = (container.w - container.y) * _Resolution.y * programAspect / _Resolution.x;
        float centerX = (container.x + container.z) * 0.5;
        stage.x = centerX - fittedWidth * 0.5;
        stage.z = centerX + fittedWidth * 0.5;
    }
    else
    {
        float fittedHeight = (container.z - container.x) * _Resolution.x / programAspect / _Resolution.y;
        float centerY = (container.y + container.w) * 0.5;
        stage.y = centerY - fittedHeight * 0.5;
        stage.w = centerY + fittedHeight * 0.5;
    }

    float insideStage = step(stage.x, c.uv.x) * step(c.uv.x, stage.z) *
                        step(stage.y, c.uv.y) * step(c.uv.y, stage.w);
    float2 stageUv = saturate((c.uv - stage.xy) / max(stage.zw - stage.xy, 1e-5.xx));
    float3 program = _Tex0.SampleLevel(LinearSampler, stageUv, 0).rgb;
    color = lerp(color, program, insideStage);

    suiComposite(color, theme.border, suiStrokeRect(c, container, 1.0));

    float4 rail = float4(0.625, 0.122, 0.956, 0.902);
    suiPanel(color, c, theme, rail, true);
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.653, 0.166), suiSectionStyle(), UI_LABEL_ANALYSIS));

    SuiTextStyle body = suiBodyStyle();
    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_TENSION.x, 0.263), body, UI_LABEL_TENSION));
    suiSlider(color, c, theme, UI_RECT_TENSION, suiInteraction(UI_INDEX_TENSION), network_tension);
    suiComposite(color, theme.text, suiInteger(c, float2(0.885, 0.263), body, (int)round(network_tension * 100.0), 3));

    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_DENSITY.x, 0.435), body, UI_LABEL_DENSITY));
    suiSlider(color, c, theme, UI_RECT_DENSITY, suiInteraction(UI_INDEX_DENSITY), ascii_density);
    suiComposite(color, theme.text, suiInteger(c, float2(0.885, 0.435), body, (int)round(ascii_density * 100.0), 3));

    suiComposite(color, theme.muted, suiLabelText(c, float2(UI_RECT_MODE.x, 0.607), body, UI_LABEL_MODE));
    bool modeState = ascii_mode != 0;
    suiButton(color, c, theme, UI_RECT_MODE, suiInteraction(UI_INDEX_MODE), modeState);
    float4 thumb = suiToggleThumb(c, theme, UI_RECT_MODE, ascii_mode ? 1.0 : 0.0);
    suiComposite(color, thumb.rgb, thumb.a);
    suiComposite(color, ascii_mode ? 0.01.xxx : theme.text, suiLabelText(c, float2(0.744, 0.673), body, ascii_mode ? UI_LABEL_ASCII_ON : UI_LABEL_VECTOR));

    suiComposite(color, theme.muted, suiLabelText(c, float2(0.653, 0.805), body, UI_LABEL_AUTO));
    suiComposite(color, theme.accent, suiLabelText(c, float2(0.653, 0.849), body, UI_LABEL_DIRECT));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
