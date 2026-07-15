#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

struct Ctrl {
    float seed; float melt; float twist; float marble_warp;
    float spread; float wire_scale; float palette; float blob_mix;
    float marble_mix; float wire_mix; float marks_mix; float feature_enabled;
    float feature_gain; float feature_count; float marker; float pad;
};

StructuredBuffer<Ctrl> _Tex0 : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

SuiTheme deskTheme()
{
    SuiTheme t = suiMonochromeTheme();
    t.background = float3(0.025, 0.026, 0.028);
    t.panel = float3(0.055, 0.057, 0.061);
    t.panelRaised = float3(0.085, 0.087, 0.091);
    t.control = float3(0.105, 0.108, 0.113);
    t.controlHover = float3(0.15, 0.15, 0.16);
    t.controlDown = float3(0.82, 0.055, 0.045);
    t.text = float3(0.92, 0.91, 0.88);
    t.muted = float3(0.47, 0.47, 0.46);
    t.border = float3(0.22, 0.22, 0.23);
    t.accent = float3(0.82, 0.055, 0.045);
    t.danger = float3(1.0, 0.22, 0.12);
    return t;
}

void label(inout float3 color, SuiContext c, SuiTheme theme, float2 p, uint id, bool strong)
{
    suiComposite(color, strong ? theme.text : theme.muted, suiLabelText(c, p, suiBodyStyle(), id));
}

void discrete(inout float3 color, SuiContext c, SuiTheme theme, float4 rect,
              SuiInteraction interaction, int selected, int count)
{
    suiButton(color, c, theme, rect, interaction, false);
    float w = (rect.z - rect.x) / max((float)count, 1.0);
    [loop] for (int i = 0; i < 6; ++i) {
        if (i >= count) break;
        float4 cell = float4(rect.x + w * i, rect.y, rect.x + w * (i + 1), rect.w);
        if (i == selected) suiComposite(color, theme.accent * 0.82, suiFillRect(c, suiRectInset(c, cell, 3.0)));
        if (i > 0) suiComposite(color, theme.border, suiLinePx(c, cell.xy, float2(cell.x, cell.w), 1.0));
    }
}

void plateSlider(inout float3 color, SuiContext c, SuiTheme theme, float4 rect,
                 SuiInteraction interaction, float value, bool hot)
{
    suiSlider(color, c, theme, rect, interaction, saturate(value * 0.5));
    float4 meter = float4(rect.x, rect.w + 0.010, rect.z, rect.w + 0.016);
    meter.z = lerp(meter.x, meter.z, saturate(value * 0.5));
    suiComposite(color, hot ? theme.accent : theme.text * 0.45, suiFillRect(c, meter));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = deskTheme();
    Ctrl data = _Tex0[0];
    float3 color = theme.background;

    suiComposite(color, float3(0.055, 0.056, 0.058), suiGridPx(c, 32.0, 0.34));
    float4 shell = float4(0.018, 0.026, 0.982, 0.968);
    suiPanel(color, c, theme, shell, false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(shell.x, shell.y, shell.z, 0.162)));
    suiComposite(color, theme.accent, suiFillRect(c, float4(shell.x, shell.y, 0.170, 0.034)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.042, 0.060), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.042, 0.116), suiBodyStyle(), UI_LABEL_SUBTITLE));

    float live = 0.55 + 0.45 * sin(_Time * 4.0) * sin(_Time * 4.0);
    float3 statusColor = data.feature_enabled > 0.5 && data.feature_count > 0.5 ? theme.accent : theme.muted;
    suiComposite(color, statusColor, suiDiscPx(c, float2(0.940, 0.092), 4.0 + live));
    suiComposite(color, theme.text, suiInteger(c, float2(0.875, 0.076), suiBodyStyle(), (int)round(data.feature_count), 3));

    float4 left = float4(0.035, 0.190, 0.485, 0.940);
    float4 right = float4(0.515, 0.190, 0.955, 0.940);
    suiPanel(color, c, theme, left, true);
    suiPanel(color, c, theme, right, true);

    label(color, c, theme, float2(0.060, 0.195), UI_LABEL_COMPOSITION, true);
    label(color, c, theme, float2(0.060, 0.225), UI_LABEL_SEED, false);
    suiSlider(color, c, theme, UI_RECT_MASTER_SEED, suiInteraction(UI_INDEX_MASTER_SEED), master_seed / 50.0);
    suiComposite(color, theme.text, suiInteger(c, float2(0.405, 0.260), suiBodyStyle(), (int)round(data.seed), 2));

    label(color, c, theme, float2(0.060, 0.360), UI_LABEL_PALETTE, false);
    discrete(color, c, theme, UI_RECT_PALETTE_VARIANT, suiInteraction(UI_INDEX_PALETTE_VARIANT), palette_variant, 5);
    label(color, c, theme, float2(0.064, 0.462), UI_LABEL_ATELIER, palette_variant == 0);
    label(color, c, theme, float2(0.145, 0.462), UI_LABEL_CHROME, palette_variant == 1);
    label(color, c, theme, float2(0.226, 0.462), UI_LABEL_POSTER, palette_variant == 2);
    label(color, c, theme, float2(0.310, 0.462), UI_LABEL_CAGE, palette_variant == 3);
    label(color, c, theme, float2(0.390, 0.462), UI_LABEL_MONO, palette_variant == 4);

    label(color, c, theme, float2(0.060, 0.510), UI_LABEL_DISTORTION, true);
    label(color, c, theme, float2(0.060, 0.545), UI_LABEL_MELT, false);
    label(color, c, theme, float2(0.270, 0.545), UI_LABEL_TWIST, false);
    suiSlider(color, c, theme, UI_RECT_MELT_MACRO, suiInteraction(UI_INDEX_MELT_MACRO), melt_macro);
    suiSlider(color, c, theme, UI_RECT_TWIST_MACRO, suiInteraction(UI_INDEX_TWIST_MACRO), twist_macro);
    label(color, c, theme, float2(0.060, 0.685), UI_LABEL_MARBLE, false);
    suiSlider(color, c, theme, UI_RECT_MARBLE_WARP_MACRO, suiInteraction(UI_INDEX_MARBLE_WARP_MACRO), marble_warp_macro / 2.5);
    label(color, c, theme, float2(0.060, 0.830), UI_LABEL_SPREAD, false);
    label(color, c, theme, float2(0.270, 0.830), UI_LABEL_WIRE_SCALE, false);
    suiSlider(color, c, theme, UI_RECT_SPREAD_MACRO, suiInteraction(UI_INDEX_SPREAD_MACRO), saturate((spread_macro - 0.4) / 1.6));
    suiSlider(color, c, theme, UI_RECT_WIRE_SCALE_MACRO, suiInteraction(UI_INDEX_WIRE_SCALE_MACRO), saturate((wire_scale_macro - 0.4) / 1.6));

    label(color, c, theme, float2(0.550, 0.195), UI_LABEL_PLATE_MIX, true);
    label(color, c, theme, float2(0.550, 0.230), UI_LABEL_SCULPTURE, false);
    plateSlider(color, c, theme, UI_RECT_BLOB_MIX, suiInteraction(UI_INDEX_BLOB_MIX), blob_mix, true);
    label(color, c, theme, float2(0.550, 0.360), UI_LABEL_MARBLE_PLATE, false);
    plateSlider(color, c, theme, UI_RECT_MARBLE_MIX, suiInteraction(UI_INDEX_MARBLE_MIX), marble_mix, false);
    label(color, c, theme, float2(0.550, 0.490), UI_LABEL_WIRE, false);
    plateSlider(color, c, theme, UI_RECT_WIRE_MIX, suiInteraction(UI_INDEX_WIRE_MIX), wire_mix, false);
    label(color, c, theme, float2(0.550, 0.620), UI_LABEL_MARKS, false);
    plateSlider(color, c, theme, UI_RECT_MARKS_MIX, suiInteraction(UI_INDEX_MARKS_MIX), marks_mix, true);

    label(color, c, theme, float2(0.550, 0.770), UI_LABEL_FEATURES, true);
    suiButton(color, c, theme, UI_RECT_FEATURE_ENABLED, suiInteraction(UI_INDEX_FEATURE_ENABLED), feature_enabled != 0);
    suiSlider(color, c, theme, UI_RECT_FEATURE_GAIN, suiInteraction(UI_INDEX_FEATURE_GAIN), feature_gain * 0.5);
    label(color, c, theme, float2(0.685, 0.805), UI_LABEL_CORNERS, false);
    suiComposite(color, statusColor, suiInteger(c, float2(0.865, 0.846), suiBodyStyle(), (int)round(data.feature_count), 3));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
