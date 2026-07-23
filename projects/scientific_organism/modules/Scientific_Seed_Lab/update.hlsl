#include "types.hlsli"

StructuredBuffer<EditorState> State : register(t0);
StructuredBuffer<StimulusRecord> Previous : register(t1);
RWStructuredBuffer<StimulusRecord> OutputBuffer : register(u0);

StimulusRecord emptyStimulus() {
    StimulusRecord s;
    s.position = 0.0.xx;
    s.direction = float2(0.0, 1.0);
    s.radius = 0.0;
    s.strength = 0.0;
    s.age = 0.0;
    s.mode = 0.0;
    s.id = 0u;
    s.flags = 0u;
    s.pad = 0.0.xx;
    return s;
}

StimulusRecord defaultStimulus(uint index) {
    StimulusRecord s = emptyStimulus();
    static const float2 positions[7] = {
        float2(0.18, 0.30), float2(0.36, 0.62), float2(0.52, 0.38),
        float2(0.68, 0.70), float2(0.82, 0.34), float2(0.28, 0.78),
        float2(0.72, 0.22)
    };
    s.position = positions[index];
    float angle = 0.8 + (float)index * 1.731;
    s.direction = float2(cos(angle), sin(angle));
    s.radius = index == 3u ? 0.16 : 0.09 + 0.012 * (float)(index % 3u);
    s.strength = index == 3u ? 1.45 : 0.82 + 0.08 * (float)(index % 4u);
    s.age = (float)index * 0.31;
    s.mode = (index == 1u || index == 4u) ? 1.0 : 0.0;
    s.id = index + 1u;
    s.flags = 1u;
    return s;
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint index = tid.x;
    if (index >= 64u) return;
    EditorState state = State[0];
    StimulusRecord stimulus = Previous[index];

    if ((uint)round(state.command) == 10u) {
        if (index < 7u) stimulus = defaultStimulus(index);
        else stimulus = emptyStimulus();
        OutputBuffer[index] = stimulus;
        return;
    }

    if ((uint)round(state.command) == 9u) {
        OutputBuffer[index] = emptyStimulus();
        return;
    }

    if (stimulusActive(stimulus)) {
        stimulus.age += min(_DeltaTime, 0.05);
    }

    int target = (int)round(state.target);
    if ((uint)round(state.command) == 1u && target == (int)index && stimulusActive(stimulus)) {
        stimulus.position = saturate(state.pointer);
        float2 delta = state.pointer - state.drag_start;
        if (dot(delta, delta) > 1e-6) stimulus.direction = normalize(float2(delta.x * 16.0 / 9.0, delta.y));
    }

    if ((uint)round(state.command) == 5u && target == (int)index && stimulusActive(stimulus)) {
        stimulus.radius = clamp(stimulus.radius * pow(1.12, state.phase), 0.02, 0.28);
    }

    if ((uint)round(state.command) == 6u && target == (int)index && stimulusActive(stimulus)) {
        stimulus.strength = clamp(stimulus.strength * pow(1.12, state.phase), 0.1, 2.5);
    }

    if ((uint)round(state.command) == 3u && target == (int)index) {
        stimulus = emptyStimulus();
    }

    if ((uint)round(state.command) == 2u) {
        bool earlierFree = false;
        [loop] for (uint i = 0u; i < index; ++i) {
            if (!stimulusActive(Previous[i])) {
                earlierFree = true;
                break;
            }
        }
        if (!earlierFree && !stimulusActive(stimulus)) {
            stimulus = emptyStimulus();
            stimulus.position = state.pointer;
            stimulus.direction = state.tool > 0.5 ? normalize(float2(-0.55, 0.84)) : float2(0.0, 1.0);
            stimulus.radius = state.radius;
            stimulus.strength = state.strength;
            stimulus.mode = state.tool > 0.5 ? 1.0 : 0.0;
            stimulus.id = state.next_id;
            stimulus.flags = 1u;
        }
    }

    OutputBuffer[index] = stimulus;
}
