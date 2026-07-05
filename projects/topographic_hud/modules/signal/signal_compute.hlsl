// signal — publishes 4 animated scalar control outputs (pulse, sweep, beat, slow)
// for driving other modules' params via expressions. Reactive-ready hook.

struct SigData { float pulse; float sweep; float beat; float slow; };
RWStructuredBuffer<SigData> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    const float TAU = 6.2831853;
    SigData s;
    s.pulse = 0.5 + 0.5 * sin(_Time * pulse_rate * TAU);
    s.sweep = frac(_Time * sweep_rate);
    s.beat  = pow(saturate(0.5 + 0.5 * sin(_Time * beat_rate * TAU)), max(beat_sharp, 0.1));
    s.slow  = 0.5 + 0.5 * sin(_Time * slow_rate * TAU);
    OutputBuffer[0] = s;
}
