#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

struct SigData {
    float pulse; float sweep; float beat; float slow;
    float terrain; float density; float blue_gain; float accent_gain;
    float nodes_gain; float labels_gain; float palette; float energy;
    float authority; float cue_mode; float master_mix; float phase;
    float marker; float pad0; float pad1; float pad2;
};

StructuredBuffer<SigData> _Tex0 : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

SuiTheme topoTheme()
{
    SuiTheme t = suiMonochromeTheme();
    t.background = float3(0.003, 0.008, 0.011);
    t.panel = float3(0.008, 0.022, 0.028);
    t.panelRaised = float3(0.012, 0.036, 0.044);
    t.control = float3(0.018, 0.055, 0.064);
    t.controlHover = float3(0.025, 0.100, 0.112);
    t.controlDown = float3(0.88, 0.44, 0.08);
    t.text = float3(0.72, 0.96, 1.00);
    t.muted = float3(0.24, 0.50, 0.56);
    t.border = float3(0.08, 0.30, 0.35);
    t.accent = float3(0.06, 0.78, 0.92);
    t.danger = float3(1.00, 0.43, 0.08);
    return t;
}

void drawDiscrete(inout float3 color, SuiContext c, SuiTheme theme, float4 rect,
                  SuiInteraction interaction, int selected, int count)
{
    suiButton(color, c, theme, rect, interaction, false);
    float width = (rect.z - rect.x) / max((float)count, 1.0);
    [loop] for (int i = 0; i < 8; ++i) {
        if (i >= count) break;
        float4 cell = float4(rect.x + width * i, rect.y, rect.x + width * (i + 1), rect.w);
        if (i == selected) suiComposite(color, theme.accent * 0.72, suiFillRect(c, suiRectInset(c, cell, 3.0)));
        if (i > 0) suiComposite(color, theme.border, suiLinePx(c, cell.xy, float2(cell.x, cell.w), 1.0));
    }
}

void label(inout float3 color, SuiContext c, SuiTheme theme, float2 p, uint id, bool hot)
{
    suiComposite(color, hot ? theme.text : theme.muted, suiLabelText(c, p, suiBodyStyle(), id));
}

void meter(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, float value, bool orange)
{
    suiControlFrame(color, c, theme, rect);
    float4 inside = suiControlInterior(c, rect);
    inside.z = lerp(inside.x, inside.z, saturate(value));
    suiComposite(color, orange ? theme.danger : theme.accent, suiFillRect(c, inside));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = topoTheme();
    SigData data = _Tex0[0];
    float3 color = theme.background;

    suiComposite(color, float3(0.008, 0.028, 0.034), suiGridPx(c, 24.0, 0.55));
    float4 shell = float4(0.018, 0.025, 0.982, 0.968);
    suiPanel(color, c, theme, shell, false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(shell.x, shell.y, shell.z, 0.165)));
    suiComposite(color, theme.accent, suiFillRect(c, float4(shell.x, shell.y, shell.x + 0.004, 0.165)));
    suiComposite(color, theme.danger, suiFillRect(c, float4(0.865, shell.y, shell.z, 0.032)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.042, 0.060), suiTitleStyle(), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.042, 0.116), suiBodyStyle(), UI_LABEL_SUBTITLE));

    float live = 0.45 + 0.55 * sin(_Time * 5.0) * sin(_Time * 5.0);
    suiComposite(color, data.authority > 1.5 ? theme.danger : theme.accent,
                 suiDiscPx(c, float2(0.936, 0.095), 4.0 + live * 1.5));
    suiComposite(color, theme.text, suiInteger(c, float2(0.884, 0.080), suiBodyStyle(), (int)round(data.energy * 100.0), 3));

    float4 left = float4(0.035, 0.190, 0.535, 0.800);
    float4 right = float4(0.555, 0.190, 0.955, 0.800);
    suiPanel(color, c, theme, left, true);
    suiPanel(color, c, theme, right, true);

    label(color, c, theme, float2(0.055, 0.195), UI_LABEL_AUTHORITY, true);
    drawDiscrete(color, c, theme, UI_RECT_AUTHORITY, suiInteraction(UI_INDEX_AUTHORITY), (int)round(authority), 3);
    label(color, c, theme, float2(0.072, 0.295), UI_LABEL_MANUAL, authority == 0);
    label(color, c, theme, float2(0.210, 0.295), UI_LABEL_AUTO, authority == 1);
    label(color, c, theme, float2(0.333, 0.295), UI_LABEL_CONDUCTOR, authority == 2);

    label(color, c, theme, float2(0.055, 0.335), UI_LABEL_CUE, true);
    drawDiscrete(color, c, theme, UI_RECT_CUE_MODE, suiInteraction(UI_INDEX_CUE_MODE), (int)round(cue_mode), 5);
    label(color, c, theme, float2(0.060, 0.435), UI_LABEL_SURVEY, cue_mode == 0);
    label(color, c, theme, float2(0.150, 0.435), UI_LABEL_THREAT, cue_mode == 1);
    label(color, c, theme, float2(0.245, 0.435), UI_LABEL_NIGHT, cue_mode == 2);
    label(color, c, theme, float2(0.327, 0.435), UI_LABEL_MINIMAL, cue_mode == 3);
    label(color, c, theme, float2(0.425, 0.435), UI_LABEL_PERFORMANCE, cue_mode == 4);

    label(color, c, theme, float2(0.055, 0.510), UI_LABEL_TERRAIN, false);
    label(color, c, theme, float2(0.300, 0.510), UI_LABEL_DENSITY, false);
    drawDiscrete(color, c, theme, UI_RECT_TERRAIN, suiInteraction(UI_INDEX_TERRAIN), terrain, 4);
    suiSlider(color, c, theme, UI_RECT_NODE_DENSITY, suiInteraction(UI_INDEX_NODE_DENSITY), saturate((node_density - 12.0) / 100.0));
    suiComposite(color, theme.text, suiInteger(c, float2(0.445, 0.565), suiBodyStyle(), (int)round(data.density), 3));

    label(color, c, theme, float2(0.055, 0.665), UI_LABEL_PALETTE, false);
    drawDiscrete(color, c, theme, UI_RECT_PALETTE, suiInteraction(UI_INDEX_PALETTE), palette, 4);
    float4 paletteStrip = float4(0.055, 0.775, 0.515, 0.786);
    float split = paletteStrip.x + (paletteStrip.z - paletteStrip.x) * 0.72;
    suiComposite(color, theme.accent, suiFillRect(c, float4(paletteStrip.x, paletteStrip.y, split, paletteStrip.w)));
    suiComposite(color, theme.danger, suiFillRect(c, float4(split, paletteStrip.y, paletteStrip.z, paletteStrip.w)));

    label(color, c, theme, float2(0.585, 0.190), UI_LABEL_LAYERS, true);
    label(color, c, theme, float2(0.585, 0.225), UI_LABEL_BLUE, false);
    suiSlider(color, c, theme, UI_RECT_LAYER_BLUE, suiInteraction(UI_INDEX_LAYER_BLUE), layer_blue * 0.5);
    label(color, c, theme, float2(0.585, 0.310), UI_LABEL_ACCENT, false);
    suiSlider(color, c, theme, UI_RECT_LAYER_ACCENT, suiInteraction(UI_INDEX_LAYER_ACCENT), layer_accent * 0.5);
    label(color, c, theme, float2(0.585, 0.400), UI_LABEL_NODES, false);
    suiSlider(color, c, theme, UI_RECT_LAYER_NODES, suiInteraction(UI_INDEX_LAYER_NODES), layer_nodes * 0.5);
    label(color, c, theme, float2(0.585, 0.490), UI_LABEL_LABELS, false);
    suiSlider(color, c, theme, UI_RECT_LAYER_LABELS, suiInteraction(UI_INDEX_LAYER_LABELS), layer_labels * 0.5);
    label(color, c, theme, float2(0.585, 0.600), UI_LABEL_MASTER, true);
    suiSlider(color, c, theme, UI_RECT_MASTER_MIX, suiInteraction(UI_INDEX_MASTER_MIX), saturate((master_mix - 0.25) / 1.5));

    // Live resolved layer readback makes control authority explicit.
    meter(color, c, theme, float4(0.585, 0.705, 0.745, 0.725), data.blue_gain * 0.5, false);
    meter(color, c, theme, float4(0.770, 0.705, 0.930, 0.725), data.accent_gain * 0.5, true);
    meter(color, c, theme, float4(0.585, 0.750, 0.745, 0.770), data.nodes_gain * 0.5, false);
    meter(color, c, theme, float4(0.770, 0.750, 0.930, 0.770), data.labels_gain * 0.5, true);

    float4 bus = float4(0.035, 0.820, 0.955, 0.945);
    suiPanel(color, c, theme, bus, false);
    label(color, c, theme, float2(0.055, 0.825), UI_LABEL_SIGNAL, true);
    suiSlider(color, c, theme, UI_RECT_MANUAL_ENERGY, suiInteraction(UI_INDEX_MANUAL_ENERGY), manual_energy);
    suiSlider(color, c, theme, UI_RECT_MANUAL_SWEEP, suiInteraction(UI_INDEX_MANUAL_SWEEP), manual_sweep);
    suiSlider(color, c, theme, UI_RECT_PULSE_RATE, suiInteraction(UI_INDEX_PULSE_RATE), pulse_rate * 0.25);
    suiSlider(color, c, theme, UI_RECT_SWEEP_RATE, suiInteraction(UI_INDEX_SWEEP_RATE), sweep_rate * 0.5);
    suiSlider(color, c, theme, UI_RECT_BEAT_RATE, suiInteraction(UI_INDEX_BEAT_RATE), beat_rate * 0.125);
    suiSlider(color, c, theme, UI_RECT_BEAT_SHARP, suiInteraction(UI_INDEX_BEAT_SHARP), saturate((beat_sharp - 0.1) / 7.9));
    meter(color, c, theme, float4(0.055, 0.925, 0.255, 0.938), data.energy, true);
    meter(color, c, theme, float4(0.275, 0.925, 0.475, 0.938), data.sweep, false);
    meter(color, c, theme, float4(0.520, 0.925, 0.690, 0.938), data.pulse, false);
    meter(color, c, theme, float4(0.710, 0.925, 0.880, 0.938), data.beat, true);

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
