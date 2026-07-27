#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct ClockState
{
    float phase01;
    float phase_unwrapped;
    float transport_seconds;
    float envelope;
    float pulse;
    float tri_wave;
    float play_gate;
    float scrub_gate;
};

StructuredBuffer<ClockState> Clock : register(t0);

float envelopeAt(float phase)
{
    float attack = smoothstep(0.0, 0.16, phase);
    float release = 1.0 - smoothstep(0.56, 0.98, phase);
    return saturate(attack * release);
}

float plotCurve(SuiContext c, float4 rect, float phase)
{
    if (c.uv.x < rect.x || c.uv.x > rect.z || c.uv.y < rect.y || c.uv.y > rect.w)
        return 0.0;

    float localX = saturate((c.uv.x - rect.x) / max(rect.z - rect.x, 0.0001));
    float localY = saturate((c.uv.y - rect.y) / max(rect.w - rect.y, 0.0001));
    float targetY = 1.0 - envelopeAt(localX);
    float curveWidth = 1.6 / max((rect.w - rect.y) * c.resolution.y, 1.0);
    return 1.0 - smoothstep(curveWidth, curveWidth * 2.2, abs(localY - targetY));
}

float labelAt(SuiContext c, uint labelId, float2 anchor, SuiTextStyle style)
{
    return suiLabelText(c, anchor, style, labelId);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y)
        return;

    SuiContext c = suiContext(DTid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    theme.accent = float3(0.96, 0.48, 0.15);

    ClockState state = Clock[0];
    float3 color = theme.background;

    float4 frame = float4(0.025, 0.035, 0.975, 0.965);
    float4 plot = float4(0.055, 0.20, 0.945, 0.72);
    suiPanel(color, c, theme, frame, false);
    suiPanel(color, c, theme, plot, true);

    float grid = suiGridPx(c, 32.0, 1.0) * suiFillRect(c, suiRectInset(c, plot, 1.0));
    suiComposite(color, float3(0.085, 0.085, 0.095), grid);
    suiComposite(color, theme.text, plotCurve(c, plot, state.phase01));

    float playheadX = lerp(plot.x, plot.z, state.phase01);
    suiComposite(color, theme.accent, suiLinePx(c, float2(playheadX, plot.y), float2(playheadX, plot.w), 2.0));
    float envY = lerp(plot.w, plot.y, state.envelope);
    suiComposite(color, theme.accent, suiDiscPx(c, float2(playheadX, envY), 5.0 + 3.0 * state.pulse));

    float4 playRect = UI_RECT_PLAY;
    float4 resetRect = UI_RECT_RESET_TRANSPORT;
    float4 scrubRect = UI_RECT_SCRUB_MODE;
    float4 positionRect = UI_RECT_SCRUB_POSITION;

    suiButton(color, c, theme, playRect, suiInteraction(0), play != 0);
    suiButton(color, c, theme, resetRect, suiInteraction(1), false);
    suiButton(color, c, theme, scrubRect, suiInteraction(2), scrub_mode != 0);
    suiSlider(color, c, theme, positionRect, suiInteraction(3), scrub_position);

    suiComposite(color, theme.text, labelAt(c, UI_LABEL_CONTROL_PLAY, float2(0.071, 0.854), suiBodyStyle()));
    suiComposite(color, theme.text, labelAt(c, UI_LABEL_CONTROL_RESET_TRANSPORT, float2(0.241, 0.854), suiBodyStyle()));
    suiComposite(color, theme.text, labelAt(c, UI_LABEL_CONTROL_SCRUB_MODE, float2(0.411, 0.854), suiBodyStyle()));
    suiComposite(color, theme.text, labelAt(c, UI_LABEL_CONTROL_SCRUB_POSITION, float2(0.621, 0.854), suiBodyStyle()));

    suiComposite(color, theme.text, labelAt(c, UI_LABEL_TITLE, float2(0.055, 0.075), suiTitleStyle()));
    suiComposite(color, theme.muted, labelAt(c, UI_LABEL_SUBTITLE, float2(0.055, 0.125), suiBodyStyle()));

    int phasePermille = (int)round(state.phase01 * 1000.0);
    int envelopePermille = (int)round(state.envelope * 1000.0);
    suiComposite(color, theme.text, suiInteger(c, float2(0.705, 0.092), suiBodyStyle(), phasePermille, 4));
    suiComposite(color, theme.accent, suiInteger(c, float2(0.835, 0.092), suiBodyStyle(), envelopePermille, 4));

    OutputUAV[DTid.xy] = float4(saturate(color), 1.0);
}
