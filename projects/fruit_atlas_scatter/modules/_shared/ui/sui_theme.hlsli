#ifndef SENTINEL_SUI_THEME_HLSLI
#define SENTINEL_SUI_THEME_HLSLI

struct SuiTheme {
    float3 background;
    float3 panel;
    float3 panelRaised;
    float3 control;
    float3 controlHover;
    float3 controlDown;
    float3 text;
    float3 muted;
    float3 border;
    float3 accent;
    float3 danger;
    float3 axisX;
    float3 axisY;
    float3 axisZ;
};

SuiTheme suiMonochromeTheme() {
    SuiTheme t;
    t.background   = float3(0.004, 0.004, 0.005);
    t.panel        = float3(0.014, 0.014, 0.016);
    t.panelRaised  = float3(0.032, 0.032, 0.036);
    t.control      = float3(0.050, 0.050, 0.056);
    t.controlHover = float3(0.080, 0.080, 0.088);
    t.controlDown  = float3(0.82, 0.82, 0.84);
    t.text         = float3(0.94, 0.94, 0.95);
    t.muted        = float3(0.40, 0.40, 0.43);
    t.border       = float3(0.27, 0.27, 0.30);
    t.accent       = float3(0.72, 0.72, 0.75);
    t.danger       = float3(0.68, 0.31, 0.32);
    t.axisX        = float3(1.00, 0.25, 0.30);
    t.axisY        = float3(0.30, 0.95, 0.38);
    t.axisZ        = float3(0.24, 0.56, 1.00);
    return t;
}

#endif

