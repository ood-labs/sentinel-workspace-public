// lfo — a self-animating low-frequency oscillator on _Time. Publishes `position` (wave * range,
// ready to drive a prompt-bank position or any ranged param) plus raw `value` (0..1) and `phase`.
// waveform: 0 Saw, 1 Triangle, 2 Sine, 3 Square. Drive a param with ref("<id>/control_outputs/position").

RWStructuredBuffer<float4> Ctrl : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float ph = frac(_Time * rate + phase_offset);   // 0..1 saw
    float saw = ph;
    float tri = 1.0 - abs(2.0 * ph - 1.0);
    float sine = 0.5 - 0.5 * cos(ph * 6.28318530718);
    float sq = ph < 0.5 ? 0.0 : 1.0;

    int wf = (int)waveform;
    float w = saw;
    if (wf == 1) w = tri;
    else if (wf == 2) w = sine;
    else if (wf == 3) w = sq;

    float pos = w * range;
    Ctrl[0] = float4(pos, w, ph, 0.0);
}
