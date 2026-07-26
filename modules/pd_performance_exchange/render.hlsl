#include "../_shared/ui/sui_theme.hlsli"
#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"

struct SuiInteraction
{
    uint flags;
    bool hovered;
    bool down;
};

SuiInteraction suiInteractionNone()
{
    SuiInteraction state;
    state.flags = 0u;
    state.hovered = false;
    state.down = false;
    return state;
}

#include "../_shared/ui/sui_controls.hlsli"
#include "_ui.generated.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> ProgramInput : register(t0);

struct ExchangeState
{
    float2 focus;
    float divergence;
    float cameraFollow;
    float printPressure;
    float marginCall;
    float activeDebt;
    float macroMass;
    float generation;
    float initialized;
    float owner;
    float pad;
};

StructuredBuffer<ExchangeState> StateInput : register(t1);

float generatedText(SuiContext c, float2 anchor, SuiTextStyle style, uint labelId)
{
    float coverage = 0.0;
    float advance = 8.0 * style.scalePx + style.trackingPx;
    [loop]
    for (int i = 0; i < uiLabelLength(labelId); ++i)
    {
        coverage = max(
            coverage,
            suiGlyph(c, anchor + float2(i * advance, 0.0) * c.invResolution, style, uiLabelCode(labelId, i))
        );
    }
    return coverage;
}

float4 pdStageRect(float2 resolution)
{
    float4 area = float4(0.018, 0.075, 0.755, 0.935);
    float2 areaPixels = (area.zw - area.xy) * resolution;
    float targetAspect = 16.0 / 9.0;
    float areaAspect = areaPixels.x / max(areaPixels.y, 1.0);
    float2 size = areaPixels;
    if (areaAspect > targetAspect)
        size.x = size.y * targetAspect;
    else
        size.y = size.x / targetAspect;
    float2 center = (area.xy + area.zw) * 0.5;
    float2 normalizedSize = size / max(resolution, float2(1.0, 1.0));
    return float4(center - normalizedSize * 0.5, center + normalizedSize * 0.5);
}

bool pdInside(float2 p, float4 rect)
{
    return all(p >= rect.xy) && all(p <= rect.zw);
}

SuiInteraction pdInteraction(float4 rect)
{
    SuiInteraction interaction = suiInteractionNone();
    interaction.hovered = pdInside(_ViewportPointerPosition, rect);
    interaction.down = interaction.hovered && ViewportButtonDown(0u);
    interaction.flags = (interaction.hovered ? 1u : 0u) | (interaction.down ? 2u : 0u);
    return interaction;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    SuiContext c = suiContext(tid.xy, float2((float)width, (float)height));
    SuiTheme theme = suiMonochromeTheme();
    float3 liability = float3(1.0, 0.31, 0.025);
    theme.accent = liability;
    theme.danger = liability;
    float3 color = theme.background;
    ExchangeState state = StateInput[0];

    float4 stageRect = pdStageRect(c.resolution);
    float stageCoverage = suiFillRect(c, stageRect);
    float2 stageUv = (c.uv - stageRect.xy) / max(stageRect.zw - stageRect.xy, float2(1e-5, 1e-5));
    float4 program = ProgramInput.SampleLevel(LinearSampler, stageUv, 0);
    color = lerp(color, program.rgb, stageCoverage);
    suiComposite(color, theme.text * 0.72, suiStrokeRect(c, stageRect, 1.5));

    float2 focusUv = stageRect.xy + saturate(state.focus * 0.5 + 0.5) * (stageRect.zw - stageRect.xy);
    float focusRing = suiRingPx(c, focusUv, 13.0 + state.marginCall * 12.0, 2.0);
    float focusCross =
        suiLinePx(c, focusUv - float2(22.0 * c.invResolution.x, 0.0), focusUv + float2(22.0 * c.invResolution.x, 0.0), 1.4) +
        suiLinePx(c, focusUv - float2(0.0, 22.0 * c.invResolution.y), focusUv + float2(0.0, 22.0 * c.invResolution.y), 1.4);
    suiComposite(color, liability, saturate(focusRing + focusCross) * stageCoverage);

    suiComposite(color, theme.text, generatedText(c, float2(stageRect.x, max(0.018, stageRect.y - 0.040)), suiSectionStyle(), UI_LABEL_STAGE));

    float4 gutter = float4(0.770, 0.045, 0.985, 0.955);
    suiPanel(color, c, theme, gutter, false);
    suiComposite(color, theme.text, generatedText(c, float2(0.790, 0.075), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, generatedText(c, float2(0.790, 0.125), suiBodyStyle(), UI_LABEL_INSTRUCTION));

    float4 flowRect = float4(0.785, 0.180, 0.970, 0.545);
    float normalizedFollow = saturate((state.cameraFollow - 0.05) / 0.80);
    suiXYPad(color, c, theme, flowRect, pdInteraction(flowRect), float2(state.divergence, 1.0 - normalizedFollow));
    suiComposite(color, theme.text, generatedText(c, float2(flowRect.x, flowRect.y - 0.038), suiBodyStyle(), UI_LABEL_FLOW));

    float4 pressureRect = float4(0.785, 0.610, 0.970, 0.685);
    float normalizedPressure = saturate((state.printPressure - 0.20) / 2.0);
    suiSlider(color, c, theme, pressureRect, pdInteraction(pressureRect), normalizedPressure);
    suiComposite(color, theme.text, generatedText(c, float2(pressureRect.x, pressureRect.y - 0.038), suiBodyStyle(), UI_LABEL_PRESSURE));

    float4 marginRect = float4(0.785, 0.755, 0.970, 0.845);
    suiButton(color, c, theme, marginRect, pdInteraction(marginRect), state.marginCall > 0.01);
    suiComposite(
        color,
        state.marginCall > 0.01 ? theme.background : theme.text,
        generatedText(c, float2(marginRect.x + 0.018, marginRect.y + 0.034), suiSectionStyle(), UI_LABEL_MARGIN)
    );

    float telemetryY = 0.885;
    suiComposite(color, theme.muted, generatedText(c, float2(0.785, telemetryY), suiBodyStyle(), UI_LABEL_ACTIVE));
    suiComposite(color, theme.text, suiInteger(c, float2(0.933, telemetryY), suiBodyStyle(), (int)state.activeDebt, 2));
    suiComposite(color, theme.muted, generatedText(c, float2(0.785, telemetryY + 0.035), suiBodyStyle(), UI_LABEL_MACRO));
    float macroBar = saturate(state.macroMass);
    float4 macroRect = float4(0.914, telemetryY + 0.030, 0.970, telemetryY + 0.052);
    suiComposite(color, theme.control, suiFillRect(c, macroRect));
    float4 macroFill = macroRect;
    macroFill.z = lerp(macroRect.x, macroRect.z, macroBar);
    suiComposite(color, liability, suiFillRect(c, macroFill));
    suiComposite(color, theme.border, suiStrokeRect(c, macroRect, 1.0));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
