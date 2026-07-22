#ifndef PROCEDURAL_BUILDING_MASSING_TYPES_HLSLI
#define PROCEDURAL_BUILDING_MASSING_TYPES_HLSLI

static const uint PB_RECORD_COUNT = 12u;
static const uint PB_OBJECT_COUNT = 5u;
static const float4 PB_PLAN_RECT = float4(0.025, 0.112, 0.975, 0.955);

struct PNode {
    float3 position; float scale;
    float kind_id; float seed; float yaw; float height;
    float width; float depth; float2 dir;
};

struct MassingState {
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

uint pbObjectForRecord(uint i) {
    if (i == 1u || i >= 6u) return 1u; // podium, site furniture and landscape
    if (i == 2u) return 2u;            // tower
    if (i == 3u) return 3u;            // crown
    if (i == 4u) return 4u;            // canopy
    if (i == 5u) return 5u;            // secondary mass
    return 0u;                          // site slab is fixed
}

float2 pbRotate(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float2 pbPlanSpan() {
    float2 pixels = max((PB_PLAN_RECT.zw - PB_PLAN_RECT.xy) * _Resolution.xy, 1.0);
    return float2(18.0 * pixels.x / pixels.y, 18.0);
}

float2 pbPlanBaseWorld(float2 uv) {
    float2 local = saturate((uv - PB_PLAN_RECT.xy) / (PB_PLAN_RECT.zw - PB_PLAN_RECT.xy));
    return float2(local.x - 0.5, 0.5 - local.y) * pbPlanSpan();
}

float2 pbPlanWorld(float2 uv, float2 viewPan, float viewZoom) {
    return pbPlanBaseWorld(uv) / max(viewZoom, 0.01) + viewPan;
}

float2 pbWorldPlan(float2 world, float2 viewPan, float viewZoom) {
    float2 local = (world - viewPan) * max(viewZoom, 0.01) / pbPlanSpan();
    local = float2(local.x + 0.5, 0.5 - local.y);
    return lerp(PB_PLAN_RECT.xy, PB_PLAN_RECT.zw, local);
}

bool pbInPlan(float2 uv) {
    return all(uv >= PB_PLAN_RECT.xy) && all(uv <= PB_PLAN_RECT.zw);
}

bool pbSelected(uint objectId) {
    for (uint i = 0u; i < min(_ViewportSelectionMeta.x, 64u); ++i)
        if (_ViewportSelectionIds[i / 4u][i % 4u] == objectId) return true;
    return false;
}

#endif
