struct ClockSignals
{
    float phase;
    float envelope;
    float pulse;
    float playing;
    float rate_value;
    float scrub_active;
    float cycle_sin;
    float cycle_cos;
};

RWStructuredBuffer<ClockSignals> OutputBuffer : register(u0);

float envelopeAt(float p)
{
    float attack = smoothstep(0.0, 0.10, p);
    float release = 1.0 - smoothstep(0.34, 0.94, p);
    float shoulder = 0.72 + 0.28 * smoothstep(0.10, 0.22, p);
    return saturate(attack * release * shoulder);
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float p = _Tex0.Load(int3(0, 0, 0)).x;
    float tau = 6.28318530718;

    ClockSignals signals;
    signals.phase = p;
    signals.envelope = envelopeAt(p);
    signals.pulse = 1.0 - smoothstep(0.0, 0.055, min(p, 1.0 - p));
    signals.playing = (play > 0 && scrub_mode == 0) ? 1.0 : 0.0;
    signals.rate_value = rate;
    signals.scrub_active = scrub_mode > 0 ? 1.0 : 0.0;
    signals.cycle_sin = sin(p * tau);
    signals.cycle_cos = cos(p * tau);
    OutputBuffer[0] = signals;
}
