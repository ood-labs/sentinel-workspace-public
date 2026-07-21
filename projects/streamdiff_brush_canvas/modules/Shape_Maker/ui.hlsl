#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float smControlValue(uint i)
{
    if (i == 0u) return shape_mode / 5.0;
    if (i == 1u) return (size - 0.08) / 0.40;
    if (i == 2u) return (aspect - 0.35) / 2.45;
    if (i == 3u) return (rotation + 180.0) / 360.0;
    if (i == 4u) return character_a;
    if (i == 5u) return character_b;
    if (i == 6u) return fill_mode / 3.0;
    if (i == 7u) return (pattern_scale - 1.0) / 15.0;
    if (i == 8u) return (pattern_angle + 180.0) / 360.0;
    if (i == 9u) return (motion_speed + 2.0) / 4.0;
    if (i == 10u) return (edge_softness - 0.001) / 0.079;
    if (i == 11u) return depth_profile / 2.0;
    return (depth_strength - 0.25) / 1.75;
}

float4 smControlRect(uint i)
{
    if (i == 0u) return UI_RECT_SHAPE_MODE;
    if (i == 1u) return UI_RECT_SIZE;
    if (i == 2u) return UI_RECT_ASPECT;
    if (i == 3u) return UI_RECT_ROTATION;
    if (i == 4u) return UI_RECT_CHARACTER_A;
    if (i == 5u) return UI_RECT_CHARACTER_B;
    if (i == 6u) return UI_RECT_FILL_MODE;
    if (i == 7u) return UI_RECT_PATTERN_SCALE;
    if (i == 8u) return UI_RECT_PATTERN_ANGLE;
    if (i == 9u) return UI_RECT_MOTION_SPEED;
    if (i == 10u) return UI_RECT_EDGE_SOFTNESS;
    if (i == 11u) return UI_RECT_DEPTH_PROFILE;
    return UI_RECT_DEPTH_STRENGTH;
}

uint smControlIndex(uint i)
{
    if (i == 0u) return UI_INDEX_SHAPE_MODE;
    if (i == 1u) return UI_INDEX_SIZE;
    if (i == 2u) return UI_INDEX_ASPECT;
    if (i == 3u) return UI_INDEX_ROTATION;
    if (i == 4u) return UI_INDEX_CHARACTER_A;
    if (i == 5u) return UI_INDEX_CHARACTER_B;
    if (i == 6u) return UI_INDEX_FILL_MODE;
    if (i == 7u) return UI_INDEX_PATTERN_SCALE;
    if (i == 8u) return UI_INDEX_PATTERN_ANGLE;
    if (i == 9u) return UI_INDEX_MOTION_SPEED;
    if (i == 10u) return UI_INDEX_EDGE_SOFTNESS;
    if (i == 11u) return UI_INDEX_DEPTH_PROFILE;
    return UI_INDEX_DEPTH_STRENGTH;
}

uint smControlLabel(uint i)
{
    if (i == 0u) return UI_LABEL_CONTROL_SHAPE_MODE;
    if (i == 1u) return UI_LABEL_CONTROL_SIZE;
    if (i == 2u) return UI_LABEL_CONTROL_ASPECT;
    if (i == 3u) return UI_LABEL_CONTROL_ROTATION;
    if (i == 4u) return UI_LABEL_CONTROL_CHARACTER_A;
    if (i == 5u) return UI_LABEL_CONTROL_CHARACTER_B;
    if (i == 6u) return UI_LABEL_CONTROL_FILL_MODE;
    if (i == 7u) return UI_LABEL_CONTROL_PATTERN_SCALE;
    if (i == 8u) return UI_LABEL_CONTROL_PATTERN_ANGLE;
    if (i == 9u) return UI_LABEL_CONTROL_MOTION_SPEED;
    if (i == 10u) return UI_LABEL_CONTROL_EDGE_SOFTNESS;
    if (i == 11u) return UI_LABEL_CONTROL_DEPTH_PROFILE;
    return UI_LABEL_CONTROL_DEPTH_STRENGTH;
}

uint smShapeLabel()
{
    int mode = clamp(shape_mode, 0, 5);
    if (mode == 0) return UI_LABEL_SHAPE_ROUND;
    if (mode == 1) return UI_LABEL_SHAPE_BOX;
    if (mode == 2) return UI_LABEL_SHAPE_CAPSULE;
    if (mode == 3) return UI_LABEL_SHAPE_TRIANGLE;
    if (mode == 4) return UI_LABEL_SHAPE_STAR;
    return UI_LABEL_SHAPE_BLOB;
}

uint smFillLabel()
{
    int mode = clamp(fill_mode, 0, 3);
    if (mode == 0) return UI_LABEL_FILL_SOLID;
    if (mode == 1) return UI_LABEL_FILL_RINGS;
    if (mode == 2) return UI_LABEL_FILL_STRIPES;
    return UI_LABEL_FILL_CHECKER;
}

void smCompactSlider(inout float3 color, SuiContext c, SuiTheme theme, uint i)
{
    float4 rect = smControlRect(i);
    SuiInteraction interaction = suiInteraction(smControlIndex(i));
    float3 face = interaction.down ? theme.controlDown : (interaction.hovered ? theme.controlHover : theme.control);
    suiComposite(color, face, suiFillRect(c, rect));
    suiComposite(color, theme.border, suiStrokeRect(c, rect, 1.0));

    float barHeight = 3.0 * c.invResolution.y;
    float4 bar = float4(rect.x, rect.w - barHeight, rect.z, rect.w);
    float4 amount = bar;
    amount.z = lerp(bar.x, bar.z, saturate(smControlValue(i)));
    float3 fill = interaction.down ? theme.text : (interaction.hovered ? theme.accent : theme.muted);
    suiComposite(color, fill, suiFillRect(c, amount));
    suiComposite(color, theme.text, suiLabelText(c, rect.xy + float2(7.0, 6.0) * c.invResolution, suiTextStyle(0.72, 0.0), smControlLabel(i)));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(id.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float3 color = theme.background;
    suiComposite(color, float3(0.016, 0.016, 0.018), suiGridPx(c, 28.0, 0.75));
    suiPanel(color, c, theme, float4(0.018, 0.025, 0.982, 0.975), false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.018, 0.025, 0.982, 0.115)));
    suiComposite(color, theme.accent, suiFillRect(c, float4(0.018, 0.025, 0.022, 0.115)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.042, 0.055), suiTextStyle(2.0, 0.22), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.690, 0.062), suiTextStyle(0.88, 0.0), UI_LABEL_STATUS));

    suiPanel(color, c, theme, float4(0.030, 0.130, 0.285, 0.935), true);
    float4 preview = UI_RECT_CENTER;
    float2 previewUv = (c.uv - preview.xy) / (preview.zw - preview.xy);
    if (all(previewUv >= 0.0) && all(previewUv <= 1.0))
        color = lerp(color, _Tex0.SampleLevel(LinearSampler, previewUv, 0).rgb, 1.0);

    SuiInteraction previewInteraction = suiInteraction(UI_INDEX_CENTER);
    float3 borderColor = previewInteraction.down ? theme.text : (previewInteraction.hovered ? theme.accent : theme.border);
    suiComposite(color, borderColor, suiStrokeRect(c, preview, 1.0));
    float2 centerMarker = lerp(preview.xy, preview.zw, center);
    suiComposite(color, theme.text, suiRingPx(c, centerMarker, previewInteraction.down ? 7.0 : 5.0, 1.5));
    suiComposite(color, theme.text, suiLabelText(c, preview.xy + float2(10.0, 10.0) * c.invResolution, suiTextStyle(0.85, 0.0), smShapeLabel()));
    suiComposite(color, theme.muted, suiLabelText(c, preview.xy + float2(10.0, 25.0) * c.invResolution, suiTextStyle(0.72, 0.0), smFillLabel()));
    suiComposite(color, theme.muted, suiLabelText(c, float2(preview.x, preview.w) + float2(0.0, 12.0) * c.invResolution, suiTextStyle(0.72, 0.0), UI_LABEL_DRAG_POSITION));

    [unroll] for (uint i = 0u; i < 13u; ++i)
        smCompactSlider(color, c, theme, i);

    OutputUAV[id.xy] = float4(saturate(color), 1.0);
}
