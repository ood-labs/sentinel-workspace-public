#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"

struct ClockState
{
    float phase01;
    float phase_unwrapped;
    float transport_seconds;
    float envelope;
    float pulse;
    float tri_wave;
    float play_gate;
    float scrub_gate;
    float reset_latch;
};

RWStructuredBuffer<ClockState> OutputState : register(u0);

float envelopeShape(float phase)
{
    float attack = smoothstep(0.0, 0.16, phase);
    float release = 1.0 - smoothstep(0.56, 0.98, phase);
    return saturate(attack * release);
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    ClockState prior = OutputState[0];
    ClockState next = prior;

    float dt = min(max(_DeltaTime, 0.0), 0.1);
    float resetDown = suiInteraction(UI_INDEX_RESET_TRANSPORT).down ? 1.0 : 0.0;
    bool wantsReset = resetDown > 0.5 && prior.reset_latch <= 0.5;
    bool isScrubbing = scrub_mode != 0;
    bool isPlaying = play != 0;
    next.reset_latch = resetDown;

    if (wantsReset)
    {
        next.phase_unwrapped = 0.0;
        next.transport_seconds = 0.0;
    }
    else if (isScrubbing)
    {
        next.phase_unwrapped = saturate(scrub_position);
        next.transport_seconds = next.phase_unwrapped / max(abs(rate), 0.0001);
    }
    else if (isPlaying)
    {
        next.phase_unwrapped += dt * rate;
        next.transport_seconds += dt;
    }

    next.phase01 = frac(max(next.phase_unwrapped, 0.0));
    next.envelope = envelopeShape(next.phase01);
    next.tri_wave = 1.0 - abs(next.phase01 * 2.0 - 1.0);

    float quarterPhase = frac(next.phase_unwrapped * 4.0);
    next.pulse = pow(saturate(1.0 - quarterPhase * 5.0), 3.0);
    next.play_gate = isPlaying && !isScrubbing ? 1.0 : 0.0;
    next.scrub_gate = isScrubbing ? 1.0 : 0.0;

    OutputState[0] = next;
}
