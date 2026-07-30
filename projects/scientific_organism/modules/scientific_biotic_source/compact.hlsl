#include "types.hlsli"

RWStructuredBuffer<StimulusRecord> OutputBuffer : register(u0);

StimulusRecord emptyStimulus() {
    StimulusRecord stimulus;
    stimulus.position = 0.0.xx;
    stimulus.direction = float2(0.0, 1.0);
    stimulus.radius = 0.0;
    stimulus.strength = 0.0;
    stimulus.age = 0.0;
    stimulus.mode = 0.0;
    stimulus.id = 0u;
    stimulus.flags = 0u;
    stimulus.pad = 0.0.xx;
    return stimulus;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    [unroll] for (uint outputIndex = 0u; outputIndex < 16u; ++outputIndex) {
        OutputBuffer[outputIndex] = emptyStimulus();
    }
    uint compactIndex = 0u;
    uint inputCount = min(_Data0_Count, 64u);
    [loop] for (uint inputIndex = 0u; inputIndex < inputCount && compactIndex < 16u; ++inputIndex) {
        if ((_Data0[inputIndex].flags & 1u) == 0u) continue;
        StimulusRecord stimulus;
        stimulus.position = _Data0[inputIndex].position;
        stimulus.direction = _Data0[inputIndex].direction;
        stimulus.radius = _Data0[inputIndex].radius;
        stimulus.strength = _Data0[inputIndex].strength;
        stimulus.age = _Data0[inputIndex].age;
        stimulus.mode = _Data0[inputIndex].mode;
        stimulus.id = _Data0[inputIndex].id;
        stimulus.flags = _Data0[inputIndex].flags;
        stimulus.pad = _Data0[inputIndex].pad;
        OutputBuffer[compactIndex] = stimulus;
        compactIndex += 1u;
    }
}
