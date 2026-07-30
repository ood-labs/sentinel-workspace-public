struct PhaseState
{
    float phase_periods;
    float running;
    float speed;
    float reserved;
};

StructuredBuffer<PhaseState> PreviousState : register(t0);
RWStructuredBuffer<PhaseState> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    PhaseState previous = PreviousState[0];
    float phase = previous.phase_periods;

    if (!isfinite(phase))
        phase = 0.0;

    float resetNow = reset_phase != 0 ? 1.0 : 0.0;
    bool resetFired = resetNow > 0.5 && previous.reserved < 0.5;

    if (resetFired)
    {
        phase = 0.0;
    }
    else if (run != 0)
    {
        // Use the host's absolute animation clock. A read/write structured
        // state buffer can cook at full cadence while its feedback value only
        // advances by sub-frame epsilon on some drivers; _Time remains the
        // authoritative wall-clock source and makes the scroll rate literal.
        phase = fmod(_Time * drift_speed, 4096.0);
    }

    PhaseState current;
    current.phase_periods = phase;
    current.running = run != 0 ? 1.0 : 0.0;
    current.speed = drift_speed;
    // Rising-edge latch. A host button parameter is a one-way value and can
    // remain at 1 forever; storing the previous bool prevents that state from
    // pinning phase to zero on every cook.
    current.reserved = resetNow;
    OutputBuffer[0] = current;
}
