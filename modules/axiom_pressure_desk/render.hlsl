#include "types.hlsli"
#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

StructuredBuffer<GestureField> Fields : register(t2);
StructuredBuffer<PressureStats> Stats : register(t3);
RWTexture2D<float4> OutputUAV : register(u0);

float rectBorder(SuiContext c, float4 rect, float width)
{
    return max(
        suiLinePx(c, rect.xy, float2(rect.z, rect.y), width),
        max(suiLinePx(c, float2(rect.z, rect.y), rect.zw, width),
        max(suiLinePx(c, rect.zw, float2(rect.x, rect.w), width),
            suiLinePx(c, float2(rect.x, rect.w), rect.xy, width))));
}

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

void drawField(inout float3 color, SuiContext c, float4 stage, GestureField field, float3 ink)
{
    if (field.active < 0.5) return;
    float2 center = stageToPanel(field.position, stage);
    float stageHeightPixels = (stage.w - stage.y) * c.resolution.y;
    float radiusPixels = field.radius * stageHeightPixels;
    float distancePixels = length((c.uv - center) * c.resolution);
    float ring = smoothstep(1.7, 0.25, abs(distancePixels - radiusPixels));
    float inner = smoothstep(1.3, 0.2, abs(distancePixels - radiusPixels * 0.62));
    float core = smoothstep(4.0, 0.3, distancePixels);
    float2 directionPanel = normalize(field.direction / max(c.resolution, 1.0));
    float2 arrowEnd = center + directionPanel * radiusPixels * 0.72;
    float arrow = smoothstep(1.6 / c.resolution.y, 0.3 / c.resolution.y,
        sdSegment(c.uv, center, arrowEnd));

    if (field.mode < 0.5)
    {
        color += ink * (ring * 0.85 + inner * 0.34 + core * 0.8);
    }
    else if (field.mode < 1.5)
    {
        float shearA = suiLinePx(c, center - float2(radiusPixels, 0.0) * c.invResolution,
            center + float2(radiusPixels, 0.0) * c.invResolution, 1.25);
        float shearB = suiLinePx(c, center - float2(0.0, radiusPixels * 0.55) * c.invResolution,
            center + float2(0.0, radiusPixels * 0.55) * c.invResolution, 0.8);
        color += ink * (ring * 0.44 + max(shearA, shearB) + arrow * 0.68);
    }
    else
    {
        float diamond = abs((c.uv.x - center.x) * c.resolution.x)
                      + abs((c.uv.y - center.y) * c.resolution.y);
        float diamondRing = smoothstep(2.0, 0.25, abs(diamond - radiusPixels));
        color += ink * (diamondRing * 0.92 + core * 0.72);
    }
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float3 accent = float3(1.0, 0.16, 0.025);
    float3 paper = float3(0.90, 0.89, 0.84);
    float3 color = theme.background;
    suiComposite(color, 0.012.xxx, suiGridPx(c, 24.0, 0.7));

    float headerHeight = 58.0 / _Resolution.y;
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.0, 0.0, 1.0, headerHeight)));
    suiComposite(color, accent, suiFillRect(c, float4(0.0, 0.0, 4.0 / _Resolution.x, headerHeight)));

    float4 stage = pressureStageRect(_Resolution.xy);
    suiComposite(color, 0.001.xxx, suiFillRect(c, stage));
    bool insideStage = insidePressureStage(c.uv, stage);
    if (insideStage)
    {
        float2 programUv = panelToStage(c.uv, stage);
        color = _Tex0.SampleLevel(LinearSampler, programUv, 0).rgb * program_exposure;
        float scan = step(0.88, frac(programUv.y * 360.0)) * 0.018;
        color += scan.xxx;

        [loop]
        for (uint i = 0u; i < min(_Data0_Count, 64u); ++i)
        {
            if (_Data0[i].active < 0.5) continue;
            float2 nodePanel = stageToPanel(_Data0[i].position, stage);
            float nodeDistance = length((c.uv - nodePanel) * c.resolution);
            float node = smoothstep(2.2, 0.3, abs(nodeDistance - lerp(2.5, 6.5, _Data0[i].weight)));
            color += paper * node * topology_overlay * 0.55;
        }
    }
    suiComposite(color, theme.border, rectBorder(c, stage, 1.0));

    drawField(color, c, stage, Fields[0], paper);
    drawField(color, c, stage, Fields[1], accent);
    drawField(color, c, stage, Fields[2], float3(0.58, 0.57, 0.52));

    float4 rail = float4(0.755, 0.105, 0.985, 0.895);
    suiComposite(color, theme.panelRaised * 0.74, suiFillRect(c, rail));
    suiComposite(color, theme.border, rectBorder(c, rail, 1.0));

    PressureStats stats = Stats[0];
    suiButton(color, c, theme, UI_RECT_PRESS_MODE, suiInteraction(UI_INDEX_PRESS_MODE), stats.current_mode < 0.5);
    suiButton(color, c, theme, UI_RECT_SHEAR_MODE, suiInteraction(UI_INDEX_SHEAR_MODE), abs(stats.current_mode - 1.0) < 0.5);
    suiButton(color, c, theme, UI_RECT_VOID_MODE, suiInteraction(UI_INDEX_VOID_MODE), stats.current_mode > 1.5);
    suiButton(color, c, theme, UI_RECT_CLEAR_FIELDS, suiInteraction(UI_INDEX_CLEAR_FIELDS), false);
    suiComposite(color, theme.text, suiLabelText(c, UI_RECT_PRESS_MODE.xy + float2(12.0, 12.0) * c.invResolution, suiBodyStyle(), UI_LABEL_PRESSURE));
    suiComposite(color, theme.text, suiLabelText(c, UI_RECT_SHEAR_MODE.xy + float2(12.0, 12.0) * c.invResolution, suiBodyStyle(), UI_LABEL_SHEAR));
    suiComposite(color, theme.text, suiLabelText(c, UI_RECT_VOID_MODE.xy + float2(12.0, 12.0) * c.invResolution, suiBodyStyle(), UI_LABEL_VOID));
    suiComposite(color, theme.text, suiLabelText(c, UI_RECT_CLEAR_FIELDS.xy + float2(12.0, 12.0) * c.invResolution, suiBodyStyle(), UI_LABEL_CLEAR));

    suiComposite(color, theme.text, suiLabelText(c, float2(0.026, 0.026), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.338, 0.031), suiBodyStyle(), UI_LABEL_SUBTITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.780, 0.125), suiBodyStyle(), UI_LABEL_KEYS));

    float meterX = 0.785;
    float meterWidth = 0.155;
    float radiusValue = saturate((stats.current_radius - 0.025) / 0.325);
    float energyValue = saturate(stats.gesture_energy / 4.0);
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.780, 0.585), suiBodyStyle(), UI_LABEL_RADIUS));
    suiComposite(color, theme.border, suiFillRect(c, float4(meterX, 0.630, meterX + meterWidth, 0.643)));
    suiComposite(color, paper, suiFillRect(c, float4(meterX, 0.630, meterX + meterWidth * radiusValue, 0.643)));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.780, 0.675), suiBodyStyle(), UI_LABEL_ENERGY));
    suiComposite(color, theme.border, suiFillRect(c, float4(meterX, 0.720, meterX + meterWidth, 0.733)));
    suiComposite(color, accent, suiFillRect(c, float4(meterX, 0.720, meterX + meterWidth * energyValue, 0.733)));

    float footerY = 1.0 - 34.0 / _Resolution.y;
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.0, footerY, 1.0, 1.0)));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.025, footerY + 8.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_FIELDS));
    suiComposite(color, theme.text, suiInteger(c, float2(0.105, footerY + 8.0 / _Resolution.y), suiBodyStyle(), (int)round(stats.active_fields), 1));
    suiComposite(color, accent, suiLabelText(c, float2(0.920, footerY + 8.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_LIVE));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
