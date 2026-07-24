#include "types.hlsli"

StructuredBuffer<GestureField> Fields : register(t0);
RWStructuredBuffer<PressureStats> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float active = 0.0;
    float energy = 0.0;
    [unroll]
    for (uint i = 0u; i < 3u; ++i)
    {
        active += Fields[i].active > 0.5 ? 1.0 : 0.0;
        energy += Fields[i].active > 0.5 ? abs(Fields[i].strength) : 0.0;
    }

    PressureStats stats;
    stats.active_fields = active;
    stats.current_mode = clamp(Fields[3].mode, 0.0, 2.0);
    stats.current_radius = Fields[3].radius;
    stats.gesture_energy = energy;
    OutputBuffer[0] = stats;
}
