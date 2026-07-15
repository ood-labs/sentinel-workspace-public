#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float4 tunerRect(uint index) {
    if (index == 0u) return UI_RECT_TITLE_SCALE;
    if (index == 1u) return UI_RECT_TITLE_WEIGHT;
    if (index == 2u) return UI_RECT_TITLE_TRACKING;
    if (index == 3u) return UI_RECT_SECTION_SCALE;
    if (index == 4u) return UI_RECT_SECTION_WEIGHT;
    if (index == 5u) return UI_RECT_SECTION_TRACKING;
    if (index == 6u) return UI_RECT_BODY_SCALE;
    if (index == 7u) return UI_RECT_BODY_WEIGHT;
    if (index == 8u) return UI_RECT_BODY_TRACKING;
    if (index == 9u) return UI_RECT_OUTER_PADDING;
    if (index == 10u) return UI_RECT_SECTION_GAP;
    if (index == 11u) return UI_RECT_CONTROL_HEIGHT;
    return UI_RECT_CONTROL_GAP;
}

uint tunerIndex(uint index) {
    if (index == 0u) return UI_INDEX_TITLE_SCALE;
    if (index == 1u) return UI_INDEX_TITLE_WEIGHT;
    if (index == 2u) return UI_INDEX_TITLE_TRACKING;
    if (index == 3u) return UI_INDEX_SECTION_SCALE;
    if (index == 4u) return UI_INDEX_SECTION_WEIGHT;
    if (index == 5u) return UI_INDEX_SECTION_TRACKING;
    if (index == 6u) return UI_INDEX_BODY_SCALE;
    if (index == 7u) return UI_INDEX_BODY_WEIGHT;
    if (index == 8u) return UI_INDEX_BODY_TRACKING;
    if (index == 9u) return UI_INDEX_OUTER_PADDING;
    if (index == 10u) return UI_INDEX_SECTION_GAP;
    if (index == 11u) return UI_INDEX_CONTROL_HEIGHT;
    return UI_INDEX_CONTROL_GAP;
}

uint tunerLabel(uint index) {
    if (index == 0u) return UI_LABEL_CONTROL_TITLE_SCALE;
    if (index == 1u) return UI_LABEL_CONTROL_TITLE_WEIGHT;
    if (index == 2u) return UI_LABEL_CONTROL_TITLE_TRACKING;
    if (index == 3u) return UI_LABEL_CONTROL_SECTION_SCALE;
    if (index == 4u) return UI_LABEL_CONTROL_SECTION_WEIGHT;
    if (index == 5u) return UI_LABEL_CONTROL_SECTION_TRACKING;
    if (index == 6u) return UI_LABEL_CONTROL_BODY_SCALE;
    if (index == 7u) return UI_LABEL_CONTROL_BODY_WEIGHT;
    if (index == 8u) return UI_LABEL_CONTROL_BODY_TRACKING;
    if (index == 9u) return UI_LABEL_CONTROL_OUTER_PADDING;
    if (index == 10u) return UI_LABEL_CONTROL_SECTION_GAP;
    if (index == 11u) return UI_LABEL_CONTROL_CONTROL_HEIGHT;
    return UI_LABEL_CONTROL_CONTROL_GAP;
}

float tunerValue(uint index) {
    if (index == 0u) return (title_scale - 1.0) / 3.0;
    if (index == 1u) return title_weight;
    if (index == 2u) return (title_tracking + 6.0) / 12.0;
    if (index == 3u) return (section_scale - 0.75) / 1.25;
    if (index == 4u) return section_weight;
    if (index == 5u) return (section_tracking + 4.0) / 8.0;
    if (index == 6u) return (body_scale - 0.75) / 1.25;
    if (index == 7u) return body_weight;
    if (index == 8u) return (body_tracking + 4.0) / 8.0;
    if (index == 9u) return (outer_padding - 12.0) / 52.0;
    if (index == 10u) return (section_gap - 8.0) / 40.0;
    if (index == 11u) return (control_height - 28.0) / 36.0;
    return (control_gap - 4.0) / 20.0;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float3 color = theme.background;
    suiComposite(color, 0.009.xxx, suiGridPx(c, 24.0, 0.8));

    suiPanel(color, c, theme, float4(0.020, 0.025, 0.980, 0.975), false);
    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.020, 0.025, 0.980, 0.108)));
    suiComposite(color, theme.text, suiFillRect(c, float4(0.020, 0.025, 0.023, 0.108)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.041, 0.052), suiTextStyle(2.0, 0.28), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.460, 0.059), suiTextStyle(1.0, 0.0), UI_LABEL_INSTRUCTION));

    suiPanel(color, c, theme, float4(0.035, 0.128, 0.425, 0.952), true);
    [unroll] for (uint row = 0u; row < 13u; ++row) {
        float4 rect = tunerRect(row);
        suiSlider(color, c, theme, rect, suiInteraction(tunerIndex(row)), tunerValue(row));
        suiComposite(color, theme.muted,
            suiLabelText(c, float2(0.052, rect.y + 0.016), suiTextStyle(1.0, 0.0), tunerLabel(row)));
    }

    float4 previewShell = float4(0.455, 0.128, 0.965, 0.952);
    suiPanel(color, c, theme, previewShell, false);
    float4 preview = suiRectInset(c, previewShell, outer_padding);
    suiPanel(color, c, theme, preview, true);

    SuiTextStyle titleStyle = suiTextStyleTracked(title_scale, title_weight, title_tracking);
    SuiTextStyle sectionStyle = suiTextStyleTracked(section_scale, section_weight, section_tracking);
    SuiTextStyle bodyStyle = suiTextStyleTracked(body_scale, body_weight, body_tracking);
    float2 contentAnchor = preview.xy + float2(0.0, 8.0) * c.invResolution;
    suiComposite(color, theme.text, suiLabelText(c, contentAnchor, titleStyle, UI_LABEL_PREVIEW_TITLE));

    float titleBlockPx = max(11.0 * title_scale, 22.0);
    float sectionY = contentAnchor.y + (titleBlockPx + section_gap) * c.invResolution.y;
    suiComposite(color, theme.muted, suiLabelText(c, float2(contentAnchor.x, sectionY), sectionStyle, UI_LABEL_PREVIEW_SECTION));

    float bodyY = sectionY + (max(11.0 * section_scale, 14.0) + section_gap) * c.invResolution.y;
    suiComposite(color, theme.text, suiLabelText(c, float2(contentAnchor.x, bodyY), bodyStyle, UI_LABEL_PREVIEW_BODY));
    suiComposite(color, theme.muted,
        suiLabelText(c, float2(contentAnchor.x, bodyY + (16.0 + section_gap * 0.5) * c.invResolution.y), bodyStyle, UI_LABEL_PREVIEW_DETAIL));

    float controlY = bodyY + (42.0 + section_gap) * c.invResolution.y;
    float4 firstControl = float4(contentAnchor.x, controlY, preview.z, controlY + control_height * c.invResolution.y);
    float4 secondControl = firstControl + float4(0.0, (control_height + control_gap) * c.invResolution.y, 0.0, (control_height + control_gap) * c.invResolution.y);
    float4 thirdControl = secondControl + float4(0.0, (control_height + control_gap) * c.invResolution.y, 0.0, (control_height + control_gap) * c.invResolution.y);
    suiSlider(color, c, theme, firstControl, suiInteractionNone(), 0.62);
    suiButton(color, c, theme, secondControl, suiInteractionNone(), true);
    suiButton(color, c, theme, thirdControl, suiInteractionNone(), true);
    float4 previewToggleThumb = suiToggleThumb(c, theme, thirdControl, 1.0);
    suiComposite(color, previewToggleThumb.rgb, previewToggleThumb.a);
    suiComposite(color, theme.text,
        suiLabelText(c, firstControl.xy + float2(12.0, max(8.0, control_height * 0.32)) * c.invResolution, bodyStyle, UI_LABEL_PREVIEW_SLIDER));
    suiComposite(color, theme.background,
        suiLabelText(c, secondControl.xy + float2(12.0, max(8.0, control_height * 0.32)) * c.invResolution, bodyStyle, UI_LABEL_PREVIEW_ACTION));
    suiComposite(color, theme.background,
        suiLabelText(c, thirdControl.xy + float2(28.0, max(8.0, control_height * 0.32)) * c.invResolution, bodyStyle, UI_LABEL_PREVIEW_TOGGLE));

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
