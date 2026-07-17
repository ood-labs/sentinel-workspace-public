#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct LFOData {
    float lfo1;
    float lfo2;
    float lfo3;
    float lfo4;
    float bias_x;
    float bias_y;
    float energy;
    float pulse;
};
StructuredBuffer<LFOData> _Tex0 : register(t0);

static const float TWO_PI = 6.28318530718;

float evalWave(float phaseValue, float shapeValue)
{
    float p = frac(phaseValue);
    uint shape = (uint)clamp(round(shapeValue), 0.0, 3.0);
    return shape == 0u ? sin(phaseValue * TWO_PI) * 0.5 + 0.5 :
           shape == 1u ? 1.0 - abs(p * 2.0 - 1.0) :
           shape == 2u ? p : step(0.5, p);
}
void drawWave(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, float speed, float shapeValue, float amplitude)
{
    suiComposite(color, theme.control * 0.55, suiFillRect(c, rect));
    suiComposite(color, theme.border * 0.65, suiStrokeRect(c, rect, 1.0));
    [unroll] for (int g = 1; g < 8; ++g) {
        float x = lerp(rect.x, rect.z, (float)g / 8.0);
        suiComposite(color, theme.border * 0.35, suiLinePx(c, float2(x, rect.y), float2(x, rect.w), 0.65));
    }
    suiComposite(color, theme.border * 0.55, suiLinePx(c, float2(rect.x, (rect.y + rect.w) * 0.5), float2(rect.z, (rect.y + rect.w) * 0.5), 0.8));

    if (c.uv.x >= rect.x && c.uv.x <= rect.z) {
        float xNorm = saturate((c.uv.x - rect.x) / max(rect.z - rect.x, 1e-5));
        float wave = evalWave(xNorm * 2.0, shapeValue) * amplitude;
        float targetY = lerp(rect.w - 0.012, rect.y + 0.012, wave);
        float lineCoverage = 1.0 - smoothstep(0.7, 2.0, abs(c.pixel.y - targetY * c.resolution.y));
        suiComposite(color, theme.text, lineCoverage);
        suiComposite(color, theme.accent * 0.45, 1.0 - smoothstep(2.0, 6.0, abs(c.pixel.y - targetY * c.resolution.y)));
    }

    float playhead = frac(_Time * master_rate * speed * 0.5);
    float playX = lerp(rect.x, rect.z, playhead);
    float liveWave = evalWave(playhead * 2.0, shapeValue) * amplitude;
    float liveY = lerp(rect.w - 0.012, rect.y + 0.012, liveWave);
    suiComposite(color, theme.text * 0.65, suiLinePx(c, float2(playX, rect.y), float2(playX, rect.w), 1.0));
    suiComposite(color, theme.text, suiDiscPx(c, float2(playX, liveY), 3.4));
}

void drawShapeBank(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, SuiInteraction interaction, float shapeValue)
{
    float gap = 2.0 * c.invResolution.x;
    float width = (rect.z - rect.x - gap * 3.0) * 0.25;
    uint selected = (uint)clamp(round(shapeValue), 0.0, 3.0);
    [unroll] for (uint i = 0u; i < 4u; ++i) {
        float x0 = rect.x + (width + gap) * (float)i;
        float4 cell = float4(x0, rect.y, x0 + width, rect.w);
        suiButton(color, c, theme, cell, interaction, selected == i);
        float y = evalWave((c.uv.x - x0) / max(width, 1e-5), (float)i);
        float target = lerp(cell.w - 0.006, cell.y + 0.006, y);
        float mask = suiFillRect(c, suiRectInset(c, cell, 4.0));
        float trace = (1.0 - smoothstep(0.5, 1.7, abs(c.pixel.y - target * c.resolution.y))) * mask;
        suiComposite(color, selected == i ? theme.background : theme.muted, trace);
    }
}

void drawLane(inout float3 color, SuiContext c, SuiTheme theme, float y0, uint labelId,
              float speed, float amplitude, float shapeValue, float value,
              float4 speedRect, uint speedIndex, float4 ampRect, uint ampIndex,
              float4 shapeRect, uint shapeIndex)
{
    float y1 = y0 + 0.165;
    float4 lane = float4(0.035, y0, 0.755, y1);
    suiPanel(color, c, theme, lane, false);
    suiComposite(color, value > 0.5 ? theme.text : theme.muted, suiFillRect(c, float4(lane.x, lane.y, lane.x + 0.003, lane.w)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.050, y0 + 0.035), suiBodyStyle(), labelId));
    suiComposite(color, theme.muted, suiInteger(c, float2(0.055, y0 + 0.085), suiTitleStyle(), (int)round(value * 100.0), 3));

    float4 waveRect = float4(0.135, y0 + 0.020, 0.505, y1 - 0.050);
    drawWave(color, c, theme, waveRect, speed, shapeValue, amplitude);
    drawShapeBank(color, c, theme, shapeRect, suiInteraction(shapeIndex), shapeValue);

    suiSlider(color, c, theme, speedRect, suiInteraction(speedIndex), saturate((speed - 0.05) / 3.95));
    suiSlider(color, c, theme, ampRect, suiInteraction(ampIndex), amplitude);
    suiComposite(color, theme.muted, suiLabelText(c, float2(speedRect.x, y0 + 0.020), suiBodyStyle(), UI_LABEL_RATE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(ampRect.x, y0 + 0.020), suiBodyStyle(), UI_LABEL_AMP));
    suiComposite(color, theme.text, suiInteger(c, float2(speedRect.x + 0.012, y0 + 0.112), suiBodyStyle(), (int)round(speed * 100.0), 3));
    suiComposite(color, theme.text, suiInteger(c, float2(ampRect.x + 0.012, y0 + 0.112), suiBodyStyle(), (int)round(amplitude * 100.0), 3));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float3 color = theme.background;
    LFOData data = _Tex0[0];

    suiComposite(color, 0.012.xxx, suiGridPx(c, 24.0, 0.65));
    float4 shell = float4(0.020, 0.030, 0.980, 0.970);
    suiPanel(color, c, theme, shell, false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(shell.x, shell.y, shell.z, 0.165)));
    suiComposite(color, theme.text, suiFillRect(c, float4(shell.x, shell.y, shell.x + 0.004, 0.165)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.045, 0.065), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.045, 0.118), suiBodyStyle(), UI_LABEL_SUBTITLE));

    suiSlider(color, c, theme, UI_RECT_MASTER_RATE, suiInteraction(UI_INDEX_MASTER_RATE), saturate((master_rate - 0.1) / 2.9));
    suiButton(color, c, theme, UI_RECT_MUTE, suiInteraction(UI_INDEX_MUTE), mute);
    float4 muteThumb = suiToggleThumb(c, theme, UI_RECT_MUTE, mute ? 1.0 : 0.0);
    suiComposite(color, muteThumb.rgb, muteThumb.a);

    drawLane(color, c, theme, 0.200, UI_LABEL_PROMPT, lfo1_speed, lfo1_amp, lfo1_shape, data.lfo1,
             UI_RECT_LFO1_SPEED, UI_INDEX_LFO1_SPEED, UI_RECT_LFO1_AMP, UI_INDEX_LFO1_AMP, UI_RECT_LFO1_SHAPE, UI_INDEX_LFO1_SHAPE);
    drawLane(color, c, theme, 0.390, UI_LABEL_ENERGY, lfo2_speed, lfo2_amp, lfo2_shape, data.lfo2,
             UI_RECT_LFO2_SPEED, UI_INDEX_LFO2_SPEED, UI_RECT_LFO2_AMP, UI_INDEX_LFO2_AMP, UI_RECT_LFO2_SHAPE, UI_INDEX_LFO2_SHAPE);
    drawLane(color, c, theme, 0.580, UI_LABEL_CAMERA, lfo3_speed, lfo3_amp, lfo3_shape, data.lfo3,
             UI_RECT_LFO3_SPEED, UI_INDEX_LFO3_SPEED, UI_RECT_LFO3_AMP, UI_INDEX_LFO3_AMP, UI_RECT_LFO3_SHAPE, UI_INDEX_LFO3_SHAPE);
    drawLane(color, c, theme, 0.770, UI_LABEL_PULSE, lfo4_speed, lfo4_amp, lfo4_shape, data.lfo4,
             UI_RECT_LFO4_SPEED, UI_INDEX_LFO4_SPEED, UI_RECT_LFO4_AMP, UI_INDEX_LFO4_AMP, UI_RECT_LFO4_SHAPE, UI_INDEX_LFO4_SHAPE);

    float4 side = float4(0.780, 0.200, 0.965, 0.950);
    suiPanel(color, c, theme, side, true);
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.800, 0.225), suiSectionStyle(), UI_LABEL_BIAS));
    suiXYPad(color, c, theme, UI_RECT_MOTION_BIAS, suiInteraction(UI_INDEX_MOTION_BIAS), motion_bias);
    suiButton(color, c, theme, UI_RECT_BURST, suiInteraction(UI_INDEX_BURST), suiInteraction(UI_INDEX_BURST).down);
    suiComposite(color, suiInteraction(UI_INDEX_BURST).down ? theme.background : theme.text,
                 suiLabelText(c, float2(0.842, 0.555), suiBodyStyle(), UI_LABEL_BURST));

    float4 meter1 = float4(0.800, 0.650, 0.950, 0.680);
    float4 meter2 = float4(0.800, 0.700, 0.950, 0.730);
    float4 meter3 = float4(0.800, 0.750, 0.950, 0.780);
    float4 meter4 = float4(0.800, 0.800, 0.950, 0.830);
    suiStatus(color, c, theme, meter1, data.lfo1);
    suiStatus(color, c, theme, meter2, data.lfo2);
    suiStatus(color, c, theme, meter3, data.lfo3);
    suiStatus(color, c, theme, meter4, data.lfo4);
    float statusPulse = 0.5 + 0.5 * sin(_Time * 5.0);
    suiComposite(color, mute ? theme.danger : theme.text, suiDiscPx(c, float2(0.815, 0.895), 4.0 + statusPulse * 1.5));
    suiComposite(color, mute ? theme.danger : theme.text,
                 suiLabelText(c, float2(0.835, 0.880), suiBodyStyle(), mute ? UI_LABEL_MUTED : UI_LABEL_LIVE));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
