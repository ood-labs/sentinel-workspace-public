// One shared phase source for the entire MIDI-controller scene.
struct MotionBus {
    float phase;
    float beat;
    float pad_energy;
    float knob_energy;
    float sweep;
    float palette;
    float loop_seconds;
    float reserved;
};

RWStructuredBuffer<MotionBus> Out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    MotionBus b;
    b.phase = frac(phase + _Time * animation_speed / max(loop_seconds, 0.1));
    b.beat = frac(b.phase * 4.0);
    b.pad_energy = pad_energy;
    b.knob_energy = knob_energy;
    b.sweep = sweep_amount;
    b.palette = (float)palette_mode;
    b.loop_seconds = loop_seconds;
    b.reserved = 0.0;
    Out[0] = b;
}
