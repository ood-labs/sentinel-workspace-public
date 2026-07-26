struct LfoState
{
    float master_phase;
    float sine;
    float triangle_value;
    float pulse;
    float ramp;
    float orbit_x;
    float orbit_y;
    float accent;
    float slow_phase;
    float slow_sine;
    float odd_phase;
    float odd_triangle;
    float envelope;
    float drift;
    float last_scrub;
    float initialized;
};

RWStructuredBuffer<LfoState> OutputBuffer : register(u0);

static const float TAU = 6.28318530718;

float triangleWave(float phase)
{
    return 1.0 - abs(frac(phase) * 2.0 - 1.0);
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    LfoState state = OutputBuffer[0];
    if (state.initialized < 0.5)
    {
        state.master_phase = 0.0;
        state.slow_phase = frac(phase_offset_b);
        state.odd_phase = frac(phase_offset_c);
        state.last_scrub = frac(max(scrub_phase, 0.0));
        state.initialized = 1.0;
    }

    float requestedScrub = frac(max(scrub_phase, 0.0));
    bool scrubChanged = abs(requestedScrub - state.last_scrub) > 0.00001;
    float safePeriod = max(period_seconds, 0.1);
    float stepValue = max(_DeltaTime, 0.0) / safePeriod;

    if (reset_phase != 0)
    {
        state.master_phase = 0.0;
        state.slow_phase = frac(phase_offset_b);
        state.odd_phase = frac(phase_offset_c);
    }
    else if (scrubChanged)
    {
        state.master_phase = requestedScrub;
        state.slow_phase = frac(requestedScrub * ratio_b + phase_offset_b);
        state.odd_phase = frac(requestedScrub * ratio_c + phase_offset_c);
    }
    else if (transport_run != 0)
    {
        state.master_phase = frac(state.master_phase + stepValue);
        state.slow_phase = frac(state.slow_phase + stepValue * max(ratio_b, 0.0));
        state.odd_phase = frac(state.odd_phase + stepValue * max(ratio_c, 0.0));
    }

    float angle = state.master_phase * TAU;
    float slowAngle = state.slow_phase * TAU;
    float oddAngle = state.odd_phase * TAU;
    state.sine = 0.5 + 0.5 * sin(angle);
    state.triangle_value = triangleWave(state.master_phase);
    state.pulse = state.master_phase < saturate(pulse_width) ? 1.0 : 0.0;
    state.ramp = state.master_phase;
    state.orbit_x = 0.5 + 0.5 * cos(angle);
    state.orbit_y = state.sine;
    state.accent = pow(saturate(0.5 + 0.5 * cos(angle)), max(accent_sharpness, 1.0));
    state.slow_sine = 0.5 + 0.5 * sin(slowAngle);
    state.odd_triangle = triangleWave(state.odd_phase);
    state.envelope = saturate(state.sine * 0.62 + state.accent * 0.38);
    float coupled = sin(angle + sin(slowAngle) * drift_coupling * 2.2 + cos(oddAngle) * drift_coupling);
    state.drift = 0.5 + 0.5 * coupled;
    state.last_scrub = requestedScrub;
    state.initialized = 1.0;
    OutputBuffer[0] = state;
}
