struct LfoState
{
    float phase;
    float sine;
    float triangle_value;
    float pulse;
    float ramp;
    float orbit_x;
    float accent;
    float last_scrub;
};

RWStructuredBuffer<LfoState> OutputBuffer : register(u0);

static const float TAU = 6.28318530718;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    LfoState previous = OutputBuffer[0];

    float phase = previous.phase;
    if (phase < 0.0 || phase >= 1.0)
        phase = 0.0;

    float requestedScrub = frac(max(scrub_phase, 0.0));
    bool scrubChanged = abs(requestedScrub - previous.last_scrub) > 0.00001;

    if (reset_phase != 0)
    {
        phase = 0.0;
    }
    else if (scrubChanged)
    {
        phase = requestedScrub;
    }
    else if (transport_run != 0)
    {
        float safePeriod = max(period_seconds, 0.1);
        phase = frac(phase + max(_DeltaTime, 0.0) / safePeriod);
    }

    float angle = phase * TAU;
    float sineValue = 0.5 + 0.5 * sin(angle);
    float triangleValue = 1.0 - abs(phase * 2.0 - 1.0);
    float pulseValue = phase < saturate(pulse_width) ? 1.0 : 0.0;
    float orbitValue = 0.5 + 0.5 * cos(angle);
    float accentValue = pow(saturate(0.5 + 0.5 * cos(angle)), max(accent_sharpness, 1.0));

    LfoState current;
    current.phase = phase;
    current.sine = sineValue;
    current.triangle_value = triangleValue;
    current.pulse = pulseValue;
    current.ramp = phase;
    current.orbit_x = orbitValue;
    current.accent = accentValue;
    current.last_scrub = requestedScrub;
    OutputBuffer[0] = current;
}
