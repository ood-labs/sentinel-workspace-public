#ifndef SCIENTIFIC_SEED_LAB_TYPES_HLSLI
#define SCIENTIFIC_SEED_LAB_TYPES_HLSLI

struct StimulusRecord {
    float2 position;
    float2 direction;
    float radius;
    float strength;
    float age;
    float mode;
    uint id;
    uint flags;
    float2 pad;
};

struct EditorState {
    float tool;
    float command;
    float phase;
    float target;
    float2 pointer;
    float2 drag_start;
    float radius;
    float strength;
    float generation;
    float drag_active;
    uint next_id;
    uint initialized;
    uint modifiers;
    uint toolbar_latch;
};

bool stimulusActive(StimulusRecord s) {
    return (s.flags & 1u) != 0u;
}

float4 seedLabStageRect() {
    float2 resolution = max(_Resolution.xy, float2(64.0, 64.0));
    float4 available = float4(20.0 / resolution.x, 78.0 / resolution.y,
                              1.0 - 20.0 / resolution.x, 1.0 - 42.0 / resolution.y);
    float2 availablePx = (available.zw - available.xy) * resolution;
    const float stageAspect = 16.0 / 9.0;
    float2 stagePx = availablePx;
    if (availablePx.x / max(availablePx.y, 1.0) > stageAspect) {
        stagePx.x = availablePx.y * stageAspect;
    } else {
        stagePx.y = availablePx.x / stageAspect;
    }
    float2 centerPx = (available.xy + available.zw) * 0.5 * resolution;
    float2 halfUv = 0.5 * stagePx / resolution;
    float2 centerUv = centerPx / resolution;
    return float4(centerUv - halfUv, centerUv + halfUv);
}

bool seedLabInsideStage(float2 panelUv) {
    float4 rect = seedLabStageRect();
    return all(panelUv >= rect.xy) && all(panelUv <= rect.zw);
}

float2 seedLabPanelToStage(float2 panelUv) {
    float4 rect = seedLabStageRect();
    return saturate((panelUv - rect.xy) / max(rect.zw - rect.xy, float2(1e-5, 1e-5)));
}

float2 seedLabStageToPanel(float2 stageUv) {
    float4 rect = seedLabStageRect();
    return lerp(rect.xy, rect.zw, stageUv);
}

#endif
