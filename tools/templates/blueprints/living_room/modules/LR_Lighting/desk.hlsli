// LR_Lighting / desk.hlsli - the lighting desk's one geometry, shared by preview.hlsl (the plan
// drawing) and layout.hlsl (type, the controls' faces, hover), so what is drawn and what is
// inspected cannot disagree. The four sliders keep the host controls' own rects (UI_RECT_*).
#ifndef LR_LIGHTING_DESK_HLSLI
#define LR_LIGHTING_DESK_HLSLI

// The record emit_lights.hlsl writes: 0 window daylight, 1-2 the pendants, 3 the floor lamp,
// 4 the table lamp, 5 the ambient fill.
struct LightRecord {
    float3 position; float type_id;
    float3 direction; float range;
    float3 color; float intensity;
    float2 size; float softness; float enabled;
};

// UI scale on the canvas's own design frame (960x540), floored so the smallest type stays >= 9 px.
float ldUiScale(float2 res) { return clamp(min(res.x / 960.0, res.y / 540.0), 0.86, 2.4); }
float ldPad(float2 res) { return max(10.0, 0.025 * res.x); }
// The room plan on the left, the control pane on the right (it holds the slider rects, which start
// at 0.32 of the height), both under a title row that stays one row tall on a tall panel.
float ldTop(float2 res) { return min(0.18 * res.y, 44.0 * ldUiScale(res)); }
float4 ldPlan(float2 res) { float p = ldPad(res); return float4(p, ldTop(res), 0.642 * res.x, res.y - p); }
float4 ldDesk(float2 res) { float p = ldPad(res); return float4(0.665 * res.x, ldTop(res), res.x - p, res.y - p); }

// The plan: aspect-correct, 10.4 x 8.4 m across the plate, +z up like the Architecture and
// Furnishings plans.
float ldPpw(float4 plan) { float2 sz = max(plan.zw - plan.xy, 1.0); return max(min(sz.x / 10.4, sz.y / 8.4), 1.0); }
float2 ldWorld(float2 px, float4 plan) {
    float2 c = (plan.xy + plan.zw) * 0.5;
    return float2(px.x - c.x, c.y - px.y) / ldPpw(plan);
}
float2 ldPx(float2 world, float4 plan) {
    float2 c = (plan.xy + plan.zw) * 0.5;
    return c + float2(world.x, -world.y) * ldPpw(plan);
}

// A practical (pendant, floor or table lamp) draws a small ring, daylight and fill a wide one.
bool ldPractical(float typeId) { return typeId > 0.5 && typeId < 2.0; }
float ldRing(float typeId) { return ldPractical(typeId) ? 0.34 : 1.10; }

// Which slider sets each record's intensity (emit_lights.hlsl): daylight, practical lamps, fill.
// Shadow softness (slider 3) sets the softness of records 0-4.
uint ldDriver(uint light) { return light == 0u ? 0u : (light <= 4u ? 1u : 2u); }
bool ldDrives(uint slider, uint light) { return slider == 3u ? light <= 4u : ldDriver(light) == slider; }

#endif
