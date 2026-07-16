#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

struct Ctrl {
    float style; float melt; float sag; float spread;
    float explode; float primary; float secondary; float twist;
    float painterly; float facet; float hue; float heat;
    float scatter; float primary_mode; float secondary_mode; float marker;
};
StructuredBuffer<Ctrl> _Tex0 : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

SuiTheme desertTheme()
{
    SuiTheme t = suiMonochromeTheme();
    t.background = float3(0.014, 0.013, 0.011);
    t.panel = float3(0.035, 0.031, 0.025);
    t.panelRaised = float3(0.070, 0.052, 0.028);
    t.control = float3(0.095, 0.075, 0.045);
    t.controlHover = float3(0.18, 0.125, 0.052);
    t.controlDown = float3(0.88, 0.42, 0.06);
    t.text = float3(0.92, 0.86, 0.72);
    t.muted = float3(0.48, 0.40, 0.29);
    t.border = float3(0.22, 0.16, 0.09);
    t.accent = float3(0.88, 0.42, 0.06);
    t.danger = float3(0.86, 0.12, 0.04);
    return t;
}

void label(inout float3 color, SuiContext c, SuiTheme theme, float2 p, uint id, bool strong)
{
    suiComposite(color, strong ? theme.text : theme.muted, suiLabelText(c, p, suiBodyStyle(), id));
}

void meter(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, SuiInteraction interaction, float value)
{
    suiSlider(color, c, theme, rect, interaction, saturate(value));
    float4 meterLine = float4(rect.x, rect.w + 0.010, lerp(rect.x, rect.z, saturate(value)), rect.w + 0.016);
    suiComposite(color, theme.accent, suiFillRect(c, meterLine));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = desertTheme();
    Ctrl data = _Tex0[0];
    float3 color = theme.background;
    suiComposite(color, float3(0.075, 0.048, 0.018), suiGridPx(c, 32.0, 0.32));

    float4 shell = float4(0.018, 0.026, 0.982, 0.968);
    suiPanel(color, c, theme, shell, false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(shell.x, shell.y, shell.z, 0.162)));
    suiComposite(color, theme.accent, suiFillRect(c, float4(shell.x, shell.y, 0.205, 0.034)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.042, 0.060), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.042, 0.116), suiBodyStyle(), UI_LABEL_SUBTITLE));
    float live = 3.5;
    suiComposite(color, theme.accent, suiDiscPx(c, float2(0.944, 0.092), live));

    float4 left = float4(0.035, 0.190, 0.485, 0.945);
    float4 right = float4(0.515, 0.190, 0.955, 0.945);
    suiPanel(color, c, theme, left, true); suiPanel(color, c, theme, right, true);

    label(color, c, theme, float2(0.060, 0.195), UI_LABEL_STRUCTURE, true);
    label(color, c, theme, float2(0.060, 0.245), UI_LABEL_MELT, false);
    label(color, c, theme, float2(0.270, 0.245), UI_LABEL_SAG, false);
    meter(color, c, theme, UI_RECT_MELT_MACRO, suiInteraction(UI_INDEX_MELT_MACRO), melt_macro / 0.6);
    meter(color, c, theme, UI_RECT_SAG_MACRO, suiInteraction(UI_INDEX_SAG_MACRO), sag_macro / 0.6);
    label(color, c, theme, float2(0.060, 0.375), UI_LABEL_SPREAD, false);
    label(color, c, theme, float2(0.270, 0.375), UI_LABEL_EXPLODE, false);
    meter(color, c, theme, UI_RECT_SPREAD_MACRO, suiInteraction(UI_INDEX_SPREAD_MACRO), (spread_macro - 0.7) / 0.7);
    meter(color, c, theme, UI_RECT_EXPLODE_MACRO, suiInteraction(UI_INDEX_EXPLODE_MACRO), explode_macro / 1.2);

    label(color, c, theme, float2(0.060, 0.545), UI_LABEL_WARP, true);
    label(color, c, theme, float2(0.060, 0.595), UI_LABEL_PRIMARY, false);
    label(color, c, theme, float2(0.270, 0.595), UI_LABEL_SECONDARY, false);
    meter(color, c, theme, UI_RECT_WARP_PRIMARY, suiInteraction(UI_INDEX_WARP_PRIMARY), warp_primary / 1.2);
    meter(color, c, theme, UI_RECT_WARP_SECONDARY, suiInteraction(UI_INDEX_WARP_SECONDARY), warp_secondary);
    label(color, c, theme, float2(0.060, 0.765), UI_LABEL_TWIST, false);
    meter(color, c, theme, UI_RECT_TWIST_MACRO, suiInteraction(UI_INDEX_TWIST_MACRO), (twist_macro + 1.0) * 0.5);

    label(color, c, theme, float2(0.550, 0.195), UI_LABEL_SURFACE, true);
    label(color, c, theme, float2(0.550, 0.265), UI_LABEL_PAINT, false);
    meter(color, c, theme, UI_RECT_PAINTERLY_MACRO, suiInteraction(UI_INDEX_PAINTERLY_MACRO), painterly_macro);
    label(color, c, theme, float2(0.550, 0.415), UI_LABEL_FACET, false);
    meter(color, c, theme, UI_RECT_FACET_MACRO, suiInteraction(UI_INDEX_FACET_MACRO), facet_macro);
    label(color, c, theme, float2(0.550, 0.565), UI_LABEL_HUE, false);
    meter(color, c, theme, UI_RECT_HUE_MACRO, suiInteraction(UI_INDEX_HUE_MACRO), hue_macro);
    label(color, c, theme, float2(0.550, 0.715), UI_LABEL_HEAT, false);
    meter(color, c, theme, UI_RECT_HEAT_MACRO, suiInteraction(UI_INDEX_HEAT_MACRO), heat_macro);
    label(color, c, theme, float2(0.550, 0.835), UI_LABEL_ACCENTS, false);
    meter(color, c, theme, UI_RECT_SCATTER_MACRO, suiInteraction(UI_INDEX_SCATTER_MACRO), scatter_macro / 80.0);
    suiComposite(color, theme.text, suiInteger(c, float2(0.870, 0.880), suiBodyStyle(), (int)round(data.scatter), 2));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
