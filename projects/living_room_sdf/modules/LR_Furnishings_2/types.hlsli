#ifndef LIVING_ROOM_FURNISHING_TYPES_HLSLI
#define LIVING_ROOM_FURNISHING_TYPES_HLSLI

static const uint LR_RECORD_COUNT = 23u;
static const uint LR_OBJECT_COUNT = 12u;
static const float LR_PLAN_TOP = 0.14;

struct PNode {
    float3 position; float scale;
    float kind_id; float seed; float yaw; float height;
    float width; float depth; float2 dir;
};

struct FurnishingState {
    float2 offset; float yaw_offset; uint object_id;
    float marker; float3 pad;
};

struct EditorState {
    float mode; float command; float active_id; float dragging;
    float2 pointer; float2 drag_start;
    float snap_enabled; float snap_step; float control_latch; float marker;
    float4 pad;
    float2 view_pan; float view_zoom; float middle_down;
};

uint lrObjectForRecord(uint i) {
    if (i == 0u || (i >= 16u && i <= 18u)) return 1u; // sofa + cushions
    if (i == 1u) return 2u;                            // left chair
    if (i == 2u) return 3u;                            // right chair
    if (i == 3u || i == 19u) return 4u;                // coffee table + decor
    if (i == 4u) return 5u;                            // ottoman
    if (i == 5u) return 6u;                            // left side table
    if (i == 6u || i == 13u) return 7u;                // right table + lamp
    if (i == 7u || i == 8u || i == 10u || i == 11u || i == 20u) return 8u; // media unit
    if (i == 9u || i == 21u || i == 22u) return 9u;    // display shelf
    if (i == 12u) return 10u;                          // floor lamp
    if (i == 14u) return 11u;                          // left plant
    return 12u;                                        // right plant
}

float2 lrRotate(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float2 lrPlanSpan() {
    float planPixelsY = max(_Resolution.y * (1.0 - LR_PLAN_TOP), 1.0);
    return float2(8.0 * _Resolution.x / planPixelsY, 8.0);
}

float2 lrPlanBaseWorld(float2 uv) {
    float planY = saturate((uv.y - LR_PLAN_TOP) / (1.0 - LR_PLAN_TOP));
    return float2(uv.x - 0.5, 0.5 - planY) * lrPlanSpan();
}

float2 lrPlanWorld(float2 uv, float2 viewPan, float viewZoom) {
    return lrPlanBaseWorld(uv) / max(viewZoom, 0.01) + viewPan;
}

float2 lrWorldPlan(float2 world, float2 viewPan, float viewZoom) {
    float2 plan = (world - viewPan) * max(viewZoom, 0.01) / lrPlanSpan();
    plan = float2(plan.x + 0.5, 0.5 - plan.y);
    plan.y = lerp(LR_PLAN_TOP, 1.0, plan.y);
    return plan;
}

bool lrSelected(uint objectId) {
    for (uint i = 0u; i < min(_ViewportSelectionMeta.x, 64u); ++i)
        if (_ViewportSelectionIds[i / 4u][i % 4u] == objectId) return true;
    return false;
}

float3 lrObjectColor(uint objectId) {
    static const float3 colors[12] = {
        float3(0.20,0.75,0.88), float3(1.00,0.45,0.22), float3(0.96,0.58,0.20),
        float3(0.95,0.72,0.28), float3(0.72,0.40,0.92), float3(0.92,0.64,0.26),
        float3(1.00,0.80,0.32), float3(0.42,0.58,0.78), float3(0.56,0.48,0.82),
        float3(1.00,0.86,0.38), float3(0.22,0.88,0.44), float3(0.18,0.74,0.38)
    };
    return colors[min(objectId, 12u) - 1u];
}

#endif
