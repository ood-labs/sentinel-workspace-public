#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct LightRecord {
    float3 position; float type_id;
    float3 direction; float range;
    float3 color; float intensity;
    float2 size; float softness; float enabled;
};
StructuredBuffer<LightRecord> Lights : register(t0);

float box2(float2 p, float2 b) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float segment2(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    return length(pa - ba * saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001)));
}

float2 rotate2(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float pnodeEdge(float2 world, float2 center, float yaw, float width, float depth, float worldPerPixel) {
    float d = box2(rotate2(world - center, -yaw), max(float2(width, depth) * 0.5, 0.025));
    return 1.0 - smoothstep(worldPerPixel * 0.55, worldPerPixel * 1.45, abs(d));
}

float normalizedDaylight() { return saturate(daylight_intensity / 3.0); }
float normalizedPractical() { return saturate(practical_intensity / 4.0); }
float normalizedAmbient() { return saturate(ambient_fill / 1.5); }
float normalizedSoftness() { return saturate((shadow_softness - 0.02) / 0.98); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint2 px = tid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    SuiContext c = suiContext(px, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    theme.background = float3(0.006, 0.009, 0.013);
    theme.panel = float3(0.012, 0.018, 0.025);
    theme.panelRaised = float3(0.020, 0.029, 0.039);
    theme.control = float3(0.029, 0.039, 0.049);
    theme.controlHover = float3(0.045, 0.060, 0.073);
    theme.controlDown = float3(0.92, 0.60, 0.24);
    theme.text = float3(0.88, 0.92, 0.95);
    theme.muted = float3(0.38, 0.47, 0.55);
    theme.border = float3(0.13, 0.20, 0.26);
    theme.accent = float3(0.94, 0.54, 0.20);

    float3 col = lerp(theme.background, float3(0.010, 0.016, 0.023), uv.y);
    suiComposite(col, float3(0.016, 0.026, 0.036), suiGridPx(c, 24.0, 0.65));

    float4 header = float4(0.025, 0.030, 0.975, 0.145);
    float4 planRect = float4(0.025, 0.180, 0.642, 0.965);
    float4 deskRect = float4(0.665, 0.180, 0.975, 0.965);
    suiPanel(col, c, theme, header, true);
    suiPanel(col, c, theme, planRect, false);
    suiPanel(col, c, theme, deskRect, false);
    suiComposite(col, theme.accent, suiFillRect(c, float4(header.x, header.y, header.x + 0.004, header.w)));

    float2 planMinPx = planRect.xy * _Resolution.xy;
    float2 planMaxPx = planRect.zw * _Resolution.xy;
    float2 planSizePx = max(planMaxPx - planMinPx, 1.0);
    float2 planCenterPx = (planMinPx + planMaxPx) * 0.5;
    float pixelsPerWorld = max(min(planSizePx.x / 10.4, planSizePx.y / 8.4), 1.0);
    float2 world = (((float2)px + 0.5) - planCenterPx) / pixelsPerWorld;
    float worldPerPixel = 1.0 / pixelsPerWorld;
    float planMask = step(planRect.x, uv.x) * step(planRect.y, uv.y) * step(uv.x, planRect.z) * step(uv.y, planRect.w);

    float2 grid = abs(frac(world + 0.5) - 0.5);
    float gridLine = 1.0 - smoothstep(worldPerPixel * 0.55, worldPerPixel * 1.35, min(grid.x, grid.y));
    col += planMask * gridLine * float3(0.020, 0.032, 0.043);
    float axisX = 1.0 - smoothstep(worldPerPixel * 0.55, worldPerPixel * 1.35, abs(world.x));
    float axisY = 1.0 - smoothstep(worldPerPixel * 0.55, worldPerPixel * 1.35, abs(world.y));
    col += planMask * (axisX + axisY) * float3(0.035, 0.075, 0.102);

    uint archCount = min(_Data0_Count, 13u);
    [loop] for (uint i = 0u; i < archCount; ++i) {
        float2 center = float2(_Data0[i].position[0], _Data0[i].position[2]);
        float edge = pnodeEdge(world, center, _Data0[i].yaw, _Data0[i].width, _Data0[i].depth, worldPerPixel);
        col += planMask * edge * float3(0.20, 0.35, 0.44);
    }

    uint furnishingCount = min(_Data1_Count, 23u);
    [loop] for (uint i = 0u; i < furnishingCount; ++i) {
        float2 center = float2(_Data1[i].position[0], _Data1[i].position[2]);
        float edge = pnodeEdge(world, center, _Data1[i].yaw, _Data1[i].width, _Data1[i].depth, worldPerPixel);
        col += planMask * edge * float3(0.15, 0.22, 0.27);
    }

    [loop] for (uint i = 0u; i < 6u; ++i) {
        LightRecord light = Lights[i];
        if (light.enabled < 0.5) continue;
        float2 center = light.position.xz;
        float isDay = 1.0 - step(0.5, light.type_id);
        float isPractical = step(0.5, light.type_id) * (1.0 - step(2.0, light.type_id));
        float radius = lerp(1.35, 0.34, isPractical);
        radius = lerp(radius, 0.88, isDay);
        float distanceToLight = length(world - center);
        float ring = 1.0 - smoothstep(worldPerPixel * 0.55, worldPerPixel * 1.55, abs(distanceToLight - radius));
        float core = 1.0 - smoothstep(worldPerPixel * 1.1, worldPerPixel * 3.4, distanceToLight);
        float glow = pow(saturate(1.0 - distanceToLight / max(radius, 0.01)), 3.0);
        float3 tint = lerp(float3(0.52, 0.70, 0.95), float3(1.00, 0.52, 0.18), isPractical);
        tint = lerp(tint, light.color, 0.38);
        col += planMask * tint * (ring * 0.74 + core * 1.05 + glow * 0.10) * saturate(0.40 + light.intensity * 0.26);
        float2 direction = normalize(light.direction.xz + float2(0.0001, 0.0001));
        float directionLine = 1.0 - smoothstep(worldPerPixel * 0.55, worldPerPixel * 1.55, segment2(world, center, center + direction * 0.62));
        col += planMask * directionLine * tint * (1.0 - isPractical) * 0.66;
    }

    suiComposite(col, theme.text, suiLabelText(c, float2(0.048, 0.055), suiTitleStyle(), UI_LABEL_TITLE));
    if (_Resolution.x >= 650.0)
        suiComposite(col, theme.muted, suiLabelText(c, float2(0.048, 0.105), suiBodyStyle(), UI_LABEL_SUBTITLE));
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.692, 0.205), suiSectionStyle(), UI_LABEL_CONTROLS));

    suiSlider(col, c, theme, UI_RECT_DAYLIGHT, suiInteraction(UI_INDEX_DAYLIGHT), normalizedDaylight());
    suiSlider(col, c, theme, UI_RECT_PRACTICAL, suiInteraction(UI_INDEX_PRACTICAL), normalizedPractical());
    suiSlider(col, c, theme, UI_RECT_AMBIENT, suiInteraction(UI_INDEX_AMBIENT), normalizedAmbient());
    suiSlider(col, c, theme, UI_RECT_SOFTNESS, suiInteraction(UI_INDEX_SOFTNESS), normalizedSoftness());

    SuiTextStyle body = suiBodyStyle();
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.692, 0.280), body, UI_LABEL_DAYLIGHT));
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.692, 0.420), body, UI_LABEL_PRACTICAL));
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.692, 0.560), body, UI_LABEL_AMBIENT));
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.692, 0.700), body, UI_LABEL_SOFTNESS));
    suiComposite(col, theme.text, suiInteger(c, float2(0.918, 0.280), body, (int)round(normalizedDaylight() * 100.0), 3));
    suiComposite(col, theme.text, suiInteger(c, float2(0.918, 0.420), body, (int)round(normalizedPractical() * 100.0), 3));
    suiComposite(col, theme.text, suiInteger(c, float2(0.918, 0.560), body, (int)round(normalizedAmbient() * 100.0), 3));
    suiComposite(col, theme.text, suiInteger(c, float2(0.918, 0.700), body, (int)round(normalizedSoftness() * 100.0), 3));

    suiComposite(col, theme.muted, suiLabelText(c, float2(0.692, 0.835), suiSectionStyle(), UI_LABEL_LEGEND));
    float4 daySwatch = float4(0.692, 0.888, 0.712, 0.922);
    float4 practicalSwatch = float4(0.788, 0.888, 0.808, 0.922);
    float4 ambientSwatch = float4(0.898, 0.888, 0.918, 0.922);
    suiComposite(col, float3(0.52, 0.70, 0.95), suiFillRect(c, daySwatch));
    suiComposite(col, float3(1.00, 0.52, 0.18), suiFillRect(c, practicalSwatch));
    suiComposite(col, float3(0.34, 0.44, 0.58), suiFillRect(c, ambientSwatch));
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.717, 0.891), body, UI_LABEL_DAY));
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.813, 0.891), body, UI_LABEL_LAMPS));
    suiComposite(col, theme.muted, suiLabelText(c, float2(0.923, 0.891), body, UI_LABEL_FILL));

    OutputUAV[px] = float4(saturate(col), 1.0);
}
