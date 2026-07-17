#ifndef LIVING_ROOM_ARCHITECTURE_TYPES_HLSLI
#define LIVING_ROOM_ARCHITECTURE_TYPES_HLSLI

static const float ARCH_PLAN_TOP = 0.18;

struct PNode {
    float3 position; float scale;
    float kind_id; float seed; float yaw; float height;
    float width; float depth; float2 dir;
};

struct ArchitectureEditorState {
    float2 view_pan;
    float view_zoom;
    float middle_down;
    float marker;
    float3 pad;
};

float2 archPlanSpan() {
    float planPixelsY = max(_Resolution.y * (1.0 - ARCH_PLAN_TOP), 1.0);
    return float2(8.0 * _Resolution.x / planPixelsY, 8.0);
}

float2 archPlanBaseWorld(float2 uv) {
    float planY = saturate((uv.y - ARCH_PLAN_TOP) / (1.0 - ARCH_PLAN_TOP));
    return float2(uv.x - 0.5, 0.5 - planY) * archPlanSpan();
}

float2 archPlanWorld(float2 uv, float2 viewPan, float viewZoom) {
    return archPlanBaseWorld(uv) / max(viewZoom, 0.01) + viewPan;
}

#endif
