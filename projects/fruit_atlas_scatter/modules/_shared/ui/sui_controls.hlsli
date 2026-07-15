#ifndef SENTINEL_SUI_CONTROLS_HLSLI
#define SENTINEL_SUI_CONTROLS_HLSLI

static const float SUI_STROKE_PX = 2.0;
static const float SUI_GUTTER_PX = 1.0;

float4 suiControlInterior(SuiContext c, float4 rect) {
    return suiRectInset(c, rect, SUI_STROKE_PX + SUI_GUTTER_PX);
}

void suiControlFrame(inout float3 color, SuiContext c, SuiTheme theme, float4 rect) {
    suiComposite(color, theme.control, suiFillRect(c, rect));
    suiComposite(color, theme.border, suiStrokeRect(c, rect, SUI_STROKE_PX));
}

void suiPanel(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, bool raised) {
    suiComposite(color, raised ? theme.panelRaised : theme.panel, suiFillRect(c, rect));
    suiComposite(color, theme.border, suiStrokeRect(c, rect, SUI_STROKE_PX));
}

void suiSeparator(inout float3 color, SuiContext c, SuiTheme theme, float2 a, float2 b) {
    suiComposite(color, theme.border, suiLinePx(c, a, b, SUI_STROKE_PX));
}

void suiButton(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, SuiInteraction interaction, bool selected) {
    suiControlFrame(color, c, theme, rect);
    float3 dynamicColor = selected ? theme.accent : (interaction.down ? theme.controlDown : (interaction.hovered ? theme.controlHover : theme.control));
    suiComposite(color, dynamicColor, suiFillRect(c, suiControlInterior(c, rect)));
}

float4 suiToggleThumb(SuiContext c, SuiTheme theme, float4 rect, float enabled) {
    float4 track = suiRectInset(c, rect, 9.0);
    float thumbWidth = min(12.0 * c.invResolution.x, max(track.z - track.x, 0.0));
    float state = saturate(enabled);
    float thumbX = lerp(track.x, track.z - thumbWidth, state);
    float4 thumb = float4(thumbX, track.y, thumbX + thumbWidth, track.w);
    return float4(lerp(theme.muted, theme.text, state), suiFillRect(c, thumb));
}

void suiSlider(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, SuiInteraction interaction, float value) {
    suiControlFrame(color, c, theme, rect);
    float4 interior = suiControlInterior(c, rect);
    float4 amount = interior;
    amount.z = lerp(interior.x, interior.z, saturate(value));
    float3 fill = interaction.down ? theme.text : (interaction.hovered ? theme.accent : theme.muted);
    suiComposite(color, fill, suiFillRect(c, amount));
}

void suiXYPad(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, SuiInteraction interaction, float2 value) {
    suiControlFrame(color, c, theme, rect);
    float4 interior = suiControlInterior(c, rect);
    float2 marker = lerp(interior.xy, interior.zw, saturate(value));
    float markerRadius = interaction.down ? 7.0 : 5.0;
    suiComposite(color, theme.muted, suiGridPx(c, 32.0, 1.0) * suiFillRect(c, interior));
    suiComposite(color, interaction.hovered ? theme.text : theme.accent, suiRingPx(c, marker, markerRadius, 2.0));
}

void suiStatus(inout float3 color, SuiContext c, SuiTheme theme, float4 rect, float level) {
    suiControlFrame(color, c, theme, rect);
    float4 interior = suiControlInterior(c, rect);
    float4 amount = interior;
    amount.z = lerp(interior.x, interior.z, saturate(level));
    suiComposite(color, theme.accent, suiFillRect(c, amount));
}

void suiMarquee(inout float3 color, SuiContext c, SuiTheme theme, float4 rect) {
    suiComposite(color, theme.accent, suiStrokeRect(c, rect, 1.5));
}

#endif

