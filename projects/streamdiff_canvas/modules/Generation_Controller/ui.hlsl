#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

StructuredBuffer<float4> State : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

void drawLabel(inout float3 color, SuiContext c, float2 anchor, uint label, float3 ink)
{
    suiComposite(color, ink,
        suiLabelText(c, anchor, suiTextStyle(0.66, 0.08), label));
}

void drawModeBank(inout float3 color, SuiContext c, SuiTheme theme)
{
    float4 r = UI_RECT_MODE;
    float width = (r.z - r.x) / 3.0;
    uint selected = (uint)clamp(round(mode), 0.0, 2.0);
    [unroll] for (uint index = 0u; index < 3u; ++index) {
        float4 cell = float4(r.x + width * index, r.y,
                            r.x + width * (index + 1u), r.w);
        float selectedCoverage = index == selected ? 1.0 : 0.0;
        suiComposite(color, lerp(theme.control, theme.text, selectedCoverage),
                     suiFillRect(c, cell));
        suiComposite(color, theme.border, suiStrokeRect(c, cell, 1.0));
    }
    float labelY = r.y + 0.027;
    drawLabel(color, c, float2(r.x + width * 0.12, labelY), UI_LABEL_MANUAL,
              selected == 0u ? theme.background : theme.text);
    drawLabel(color, c, float2(r.x + width * 1.08, labelY), UI_LABEL_INTERVAL,
              selected == 1u ? theme.background : theme.text);
    drawLabel(color, c, float2(r.x + width * 2.03, labelY), UI_LABEL_CONTINUOUS,
              selected == 2u ? theme.background : theme.text);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;

    float2 resolution = float2(width, height);
    SuiContext c = suiContext(id.xy, resolution);
    SuiTheme theme = suiMonochromeTheme();
    float4 outputState = State[0];
    float3 color = theme.background;

    suiComposite(color, theme.panel, suiFillRect(c, float4(0.0, 0.0, 1.0, 0.165)));
    suiComposite(color, theme.border, suiLinePx(c, float2(0.0, 0.165), float2(1.0, 0.165), 1.0));
    drawModeBank(color, c, theme);

    suiButton(color, c, theme, UI_RECT_TRANSPORT, suiInteraction(UI_INDEX_TRANSPORT), transport_run != 0);
    suiButton(color, c, theme, UI_RECT_LINKED, suiInteraction(UI_INDEX_LINKED), link_stamps != 0);
    suiButton(color, c, theme, UI_RECT_GENERATE, suiInteraction(UI_INDEX_GENERATE), generate != 0);
    suiButton(color, c, theme, UI_RECT_NEXT, suiInteraction(UI_INDEX_NEXT), next_prompt != 0);
    drawLabel(color, c, UI_RECT_TRANSPORT.xy + float2(0.026, 0.039), UI_LABEL_RUN,
              transport_run != 0 ? theme.background : theme.text);
    drawLabel(color, c, UI_RECT_LINKED.xy + float2(0.018, 0.039), UI_LABEL_LINKED,
              link_stamps != 0 ? theme.background : theme.text);
    drawLabel(color, c, UI_RECT_GENERATE.xy + float2(0.018, 0.039), UI_LABEL_GENERATE,
              generate != 0 ? theme.background : theme.text);
    drawLabel(color, c, UI_RECT_NEXT.xy + float2(0.015, 0.039), UI_LABEL_NEXT,
              next_prompt != 0 ? theme.background : theme.text);

    float4 body = float4(0.020, 0.195, 0.980, 0.965);
    suiPanel(color, c, theme, body, false);
    suiSlider(color, c, theme, UI_RECT_PROMPT_RATE,
              suiInteraction(UI_INDEX_PROMPT_RATE), saturate(prompt_rate / 8.0));
    suiSlider(color, c, theme, UI_RECT_STAMP_SPEED,
              suiInteraction(UI_INDEX_STAMP_SPEED),
              saturate((stamp_rate - 0.5) / 19.5));
    drawLabel(color, c, float2(UI_RECT_PROMPT_RATE.x, UI_RECT_PROMPT_RATE.y - 0.050),
              UI_LABEL_PROMPT_RATE, theme.muted);
    drawLabel(color, c, float2(UI_RECT_STAMP_SPEED.x, UI_RECT_STAMP_SPEED.y - 0.050),
              UI_LABEL_STAMP_SPEED, theme.muted);

    float count = max((float)prompt_count, 1.0);
    float promptRelative = outputState.y - prompt_start;
    float promptNormalized = frac(promptRelative / count);
    float4 track = float4(0.050, 0.475, 0.950, 0.615);
    suiComposite(color, theme.control, suiFillRect(c, track));
    suiComposite(color, theme.border, suiStrokeRect(c, track, 1.0));

    uint tickCount = (uint)min(max(prompt_count, 1), 64);
    [loop] for (uint tickIndex = 0u; tickIndex < tickCount; ++tickIndex) {
        float x = lerp(track.x, track.z,
                       ((float)tickIndex + 0.5) / max((float)tickCount, 1.0));
        float selectedDistance = abs(frac(((float)tickIndex + 0.5) / tickCount - promptNormalized + 0.5) - 0.5);
        float heightScale = selectedDistance < (0.5 / tickCount) ? 0.80 : 0.32;
        suiComposite(color, selectedDistance < (0.5 / tickCount) ? theme.text : theme.muted,
                     suiLinePx(c, float2(x, lerp(track.y, track.w, 0.5 - heightScale * 0.5)),
                                  float2(x, lerp(track.y, track.w, 0.5 + heightScale * 0.5)), 1.0));
    }

    float promptX = lerp(track.x, track.z, promptNormalized);
    suiComposite(color, float3(1.0, 0.42, 0.09),
                 suiLinePx(c, float2(promptX, track.y - 0.018),
                              float2(promptX, track.w + 0.018), 2.0));

    drawLabel(color, c, float2(0.050, 0.755), UI_LABEL_PROMPT, theme.muted);
    suiComposite(color, theme.text,
        suiInteger(c, float2(0.155, 0.735), suiTextStyle(1.40, 0.12),
                   (int)floor(outputState.y), 2));
    drawLabel(color, c, float2(0.330, 0.755), UI_LABEL_CYCLE, theme.muted);
    suiComposite(color, theme.text,
        suiInteger(c, float2(0.425, 0.735), suiTextStyle(1.40, 0.12),
                   (int)floor(outputState.w), 4));

    bool held = outputState.x > 0.5;
    float4 statusRect = float4(0.800, 0.710, 0.950, 0.840);
    suiComposite(color, held ? theme.control : float3(1.0, 0.42, 0.09),
                 suiFillRect(c, statusRect));
    suiComposite(color, theme.border, suiStrokeRect(c, statusRect, 1.0));
    drawLabel(color, c, statusRect.xy + float2(0.014, 0.039),
              held ? UI_LABEL_HELD : UI_LABEL_GENERATING,
              held ? theme.text : theme.background);

    OutputUAV[id.xy] = float4(saturate(color), 1.0);
}
