#include "types.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"

StructuredBuffer<StimulusRecord> Stimuli : register(t0);
RWStructuredBuffer<EditorState> OutputBuffer : register(u0);

int hitStimulus(float2 p, float maxDistance) {
    int bestIndex = -1;
    float best = maxDistance;
    [loop] for (int i = 0; i < 64; ++i) {
        StimulusRecord s = Stimuli[i];
        if (!stimulusActive(s)) continue;
        float2 d = p - s.position;
        d.x *= 16.0 / 9.0;
        float distanceToSeed = length(d);
        if (distanceToSeed < best) {
            best = distanceToSeed;
            bestIndex = i;
        }
    }
    return bestIndex;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    EditorState state = OutputBuffer[0];
    state.command = 0.0;
    state.phase = 0.0;

    if (state.initialized == 0u) {
        state.tool = 0.0;
        state.radius = max(seed_radius, 0.02);
        state.strength = seed_strength;
        state.generation = 1.0;
        state.next_id = 16u;
        state.initialized = 1u;
        state.command = 10.0;
    }

    state.radius = seed_radius;
    state.strength = seed_strength;

    uint down = (suiInteraction(UI_INDEX_SEED).down ? 1u : 0u)
              | (suiInteraction(UI_INDEX_VORTEX).down ? 2u : 0u)
              | (suiInteraction(UI_INDEX_ERASE).down ? 4u : 0u)
              | (suiInteraction(UI_INDEX_CLEAR).down ? 8u : 0u);
    uint pressed = down & ~state.toolbar_latch;
    state.toolbar_latch = down;
    if ((pressed & 1u) != 0u) state.tool = 0.0;
    if ((pressed & 2u) != 0u) state.tool = 1.0;
    if ((pressed & 4u) != 0u) state.tool = 2.0;
    if ((pressed & 8u) != 0u) {
        state.command = 9.0;
        state.generation += 1.0;
    }

    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent eventRecord = _ViewportEvents[i];
        if (eventRecord.type == 4u && eventRecord.phase == 1u) {
            if (eventRecord.code == 17u) state.tool = 0.0; // Q
            if (eventRecord.code == 23u) state.tool = 1.0; // W
            if (eventRecord.code == 5u)  state.tool = 2.0; // E
            if (eventRecord.code == 24u) {                // X
                state.command = 9.0;
                state.generation += 1.0;
            }
        }

        if (eventRecord.type == 3u) {
            float notches = abs(eventRecord.value) > 0.001
                ? eventRecord.value
                : eventRecord.delta.y;
            if (state.drag_active > 0.5 && (int)round(state.target) >= 0
                && abs(notches) > 1e-5) {
                bool strengthWheel = (eventRecord.modifiers & VIEWPORT_MODIFIER_ALT) != 0u;
                state.command = strengthWheel ? 6.0 : 5.0;
                state.phase = notches;
                state.generation += 1.0;
            }
            continue;
        }

        if (eventRecord.type != 5u || eventRecord.device != 0u) continue;
        bool insideStage = seedLabInsideStage(eventRecord.position);
        float2 p = seedLabPanelToStage(eventRecord.position);

        if (eventRecord.code == 1u && eventRecord.phase == 7u) {
            if (!insideStage) continue;
            int hit = hitStimulus(p, max(0.035, state.radius * 0.5));
            state.pointer = p;
            state.target = (float)hit;
            if (state.tool > 1.5) {
                if (hit >= 0) {
                    state.command = 3.0;
                    state.generation += 1.0;
                }
            } else {
                state.command = 2.0;
                state.generation += 1.0;
                state.next_id += 1u;
            }
        }

        if (eventRecord.code != 3u) continue;
        if (eventRecord.phase == 5u) {
            if (!insideStage) continue;
            int hit = hitStimulus(p, max(0.045, state.radius * 0.6));
            state.target = (float)hit;
            state.drag_start = p;
            state.pointer = p;
            state.drag_active = hit >= 0 ? 1.0 : 0.0;
            state.modifiers = 0u;
            if (state.tool > 1.5 && hit >= 0) {
                state.command = 3.0;
                state.generation += 1.0;
                state.drag_active = 0.0;
            } else if (hit >= 0) {
                state.command = 1.0;
                state.generation += 1.0;
            }
        } else if ((eventRecord.phase == 6u || eventRecord.phase == 7u) && state.drag_active > 0.5) {
            state.pointer = p;
            state.command = 1.0;
            state.generation += 1.0;
            if (eventRecord.phase == 7u) {
                state.drag_active = 0.0;
                state.modifiers = 0u;
            }
        } else if (eventRecord.phase == 8u) {
            state.drag_active = 0.0;
            state.modifiers = 0u;
        }
    }

    if (state.generation > 100000.0) state.generation = 1.0;
    OutputBuffer[0] = state;
}
