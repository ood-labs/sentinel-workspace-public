#include "types.hlsli"

StructuredBuffer<StimulusRecord> Stimuli : register(t0);
RWStructuredBuffer<StimulusRecord> OutputBuffer : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= 64u) return;
    OutputBuffer[tid.x] = Stimuli[tid.x];
}
