#include "types.hlsli"
#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

StructuredBuffer<DeckState> State : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float rectBorder(SuiContext c, float4 r, float width)
{
    return max(
        suiLinePx(c, r.xy, float2(r.z, r.y), width),
        max(suiLinePx(c, float2(r.z, r.y), r.zw, width),
        max(suiLinePx(c, r.zw, float2(r.x, r.w), width),
            suiLinePx(c, float2(r.x, r.w), r.xy, width))));
}

void drawPad(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, float2 value, float3 accent)
{
    suiComposite(color, theme.panel, suiFillRect(c, rect));
    suiComposite(color, theme.border, rectBorder(c, rect, 1.0));
    float2 center = (rect.xy + rect.zw) * 0.5;
    suiComposite(color, theme.border, suiLinePx(c, float2(center.x, rect.y), float2(center.x, rect.w), 1.0));
    suiComposite(color, theme.border, suiLinePx(c, float2(rect.x, center.y), float2(rect.z, center.y), 1.0));
    float2 handle = padHandle(value, rect);
    float distancePx = length((c.uv - handle) * c.resolution);
    float halo = exp(-distancePx * distancePx / 160.0);
    float ring = smoothstep(1.6, 0.2, abs(distancePx - 7.0));
    float core = smoothstep(4.0, 0.5, distancePx);
    color += accent * (halo * 0.14 + ring * 0.9 + core * 0.75);
    suiComposite(color, accent, suiLinePx(c, float2(handle.x, rect.y), float2(handle.x, rect.w), 0.75) * 0.34);
    suiComposite(color, accent, suiLinePx(c, float2(rect.x, handle.y), float2(rect.z, handle.y), 0.75) * 0.34);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    DeckState state = State[0];
    float3 amber = float3(1.0, 0.27, 0.035);
    float3 color = theme.background;
    suiComposite(color, 0.011.xxx, suiGridPx(c, 24.0, 0.7));

    float headerHeight = 58.0 / _Resolution.y;
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.0, 0.0, 1.0, headerHeight)));
    suiComposite(color, amber, suiFillRect(c, float4(0.0, 0.0, 4.0 / _Resolution.x, headerHeight)));

    float4 stage = programStageRect(_Resolution.xy);
    suiComposite(color, 0.002.xxx, suiFillRect(c, stage));
    bool insideStage = all(c.uv >= stage.xy) && all(c.uv <= stage.zw);
    if (insideStage)
    {
        float2 programUv = saturate((c.uv - stage.xy) / max(stage.zw - stage.xy, 1e-5));
        color = _Tex0.SampleLevel(LinearSampler, programUv, 0).rgb;
        float scan = step(0.86, frac(programUv.y * 360.0)) * 0.025;
        color += scan.xxx;
    }
    suiComposite(color, theme.border, rectBorder(c, stage, 1.0));

    float4 rail = float4(0.735, 0.082, 0.985, 0.925);
    suiComposite(color, theme.panelRaised * 0.72, suiFillRect(c, rail));
    suiComposite(color, theme.border, rectBorder(c, rail, 1.0));

    drawPad(color, c, theme, energyPadRect(), float2(state.energy, state.warp), amber);
    drawPad(color, c, theme, structurePadRect(), float2(state.topology, state.relief), float3(0.88, 0.86, 0.78));
    drawPad(color, c, theme, memoryPadRect(), float2(state.memory, state.archive), float3(0.58, 0.57, 0.52));

    suiComposite(color, theme.text, suiLabelText(c, float2(0.022, 0.022), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.355, 0.026), suiBodyStyle(), UI_LABEL_KEYS));
    suiButton(color, c, theme, UI_RECT_OBSERVE, suiInteraction(UI_INDEX_OBSERVE), false);
    suiButton(color, c, theme, UI_RECT_SURGE, suiInteraction(UI_INDEX_SURGE), false);
    suiButton(color, c, theme, UI_RECT_ARCHIVE, suiInteraction(UI_INDEX_ARCHIVE), false);
    suiButton(color, c, theme, UI_RECT_BALANCED, suiInteraction(UI_INDEX_BALANCED), false);
    suiComposite(color, theme.text, suiLabelText(c, UI_RECT_OBSERVE.xy + float2(8.0, 7.0) * c.invResolution, suiBodyStyle(), UI_LABEL_OBSERVE));
    suiComposite(color, theme.text, suiLabelText(c, UI_RECT_SURGE.xy + float2(8.0, 7.0) * c.invResolution, suiBodyStyle(), UI_LABEL_SURGE));
    suiComposite(color, theme.text, suiLabelText(c, UI_RECT_ARCHIVE.xy + float2(8.0, 7.0) * c.invResolution, suiBodyStyle(), UI_LABEL_ARCHIVE));
    suiComposite(color, theme.text, suiLabelText(c, UI_RECT_BALANCED.xy + float2(8.0, 7.0) * c.invResolution, suiBodyStyle(), UI_LABEL_BALANCED));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.752, 0.098), suiBodyStyle(), UI_LABEL_ENERGY));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.858, 0.100), suiBodyStyle(), UI_LABEL_ENERGY_AXES));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.752, 0.366), suiBodyStyle(), UI_LABEL_STRUCTURE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.850, 0.368), suiBodyStyle(), UI_LABEL_STRUCTURE_AXES));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.752, 0.634), suiBodyStyle(), UI_LABEL_MEMORY));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.848, 0.636), suiBodyStyle(), UI_LABEL_MEMORY_AXES));

    float footerY = 1.0 - 36.0 / _Resolution.y;
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.0, footerY, 1.0, 1.0)));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.025, footerY + 9.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_EN));
    suiComposite(color, theme.text, suiInteger(c, float2(0.061, footerY + 9.0 / _Resolution.y), suiBodyStyle(), (int)round(state.energy * 100.0), 3));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.110, footerY + 9.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_WP));
    suiComposite(color, theme.text, suiInteger(c, float2(0.146, footerY + 9.0 / _Resolution.y), suiBodyStyle(), (int)round(state.warp * 100.0), 3));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.195, footerY + 9.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_TP));
    suiComposite(color, theme.text, suiInteger(c, float2(0.231, footerY + 9.0 / _Resolution.y), suiBodyStyle(), (int)round(state.topology * 100.0), 3));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.280, footerY + 9.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_RF));
    suiComposite(color, theme.text, suiInteger(c, float2(0.316, footerY + 9.0 / _Resolution.y), suiBodyStyle(), (int)round(state.relief * 100.0), 3));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.365, footerY + 9.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_MM));
    suiComposite(color, theme.text, suiInteger(c, float2(0.401, footerY + 9.0 / _Resolution.y), suiBodyStyle(), (int)round(state.memory * 100.0), 3));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.450, footerY + 9.0 / _Resolution.y), suiBodyStyle(), UI_LABEL_AR));
    suiComposite(color, theme.text, suiInteger(c, float2(0.486, footerY + 9.0 / _Resolution.y), suiBodyStyle(), (int)round(state.archive * 100.0), 3));
    suiComposite(color, state.quality > 0.5 ? amber : theme.muted,
        suiLabelText(c, float2(0.925, footerY + 9.0 / _Resolution.y), suiBodyStyle(),
                     state.quality > 0.5 ? UI_LABEL_HERO : UI_LABEL_PERF));
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
