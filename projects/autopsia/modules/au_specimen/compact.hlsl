// AUTOPSIA — compact incoming operator stimuli into a fixed 16-slot bank.
#include "types.hlsli"

RWStructuredBuffer<StimulusRecord> StimOut : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    [unroll] for (uint i = 0u; i < 16u; ++i) {
        StimOut[i] = emptyStimulus();
    }
    uint compact = 0u;
    uint count = min(_Data0_Count, 64u);
    [loop] for (uint r = 0u; r < count && compact < 16u; ++r) {
        if ((_Data0[r].flags & 1u) == 0u) continue;
        StimulusRecord s;
        s.position = _Data0[r].position;
        s.direction = _Data0[r].direction;
        s.radius = _Data0[r].radius;
        s.strength = _Data0[r].strength;
        s.age = _Data0[r].age;
        s.mode = _Data0[r].mode;
        s.id = _Data0[r].id;
        s.flags = _Data0[r].flags;
        s.pad = _Data0[r].pad;
        StimOut[compact] = s;
        compact += 1u;
    }
}
