struct LFOData {
    float lfo1;
    float lfo2;
    float lfo3;
    float lfo4;
    float bias_x;
    float bias_y;
    float energy;
    float pulse;
};

RWStructuredBuffer<LFOData> OutputBuffer : register(u0);

static const float TWO_PI = 6.28318530718;

float evalLFO(float t, float speed, float amplitude, float shapeValue)
{
    float phaseValue = t * speed;
    float p = frac(phaseValue);
    uint shape = (uint)clamp(round(shapeValue), 0.0, 3.0);
    float raw = shape == 0u ? sin(phaseValue * TWO_PI) * 0.5 + 0.5 :
                shape == 1u ? 1.0 - abs(p * 2.0 - 1.0) :
                shape == 2u ? p : step(0.5, p);
    return saturate(raw * amplitude);
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float t = _Time * master_rate;
    LFOData d;
    d.lfo1 = evalLFO(t, lfo1_speed, lfo1_amp, lfo1_shape);
    d.lfo2 = evalLFO(t, lfo2_speed, lfo2_amp, lfo2_shape);
    d.lfo3 = evalLFO(t, lfo3_speed, lfo3_amp, lfo3_shape);
    d.lfo4 = evalLFO(t, lfo4_speed, lfo4_amp, lfo4_shape);
    if (mute) d.lfo1 = d.lfo2 = d.lfo3 = d.lfo4 = 0.0;
    d.bias_x = motion_bias.x;
    d.bias_y = motion_bias.y;
    d.energy = (d.lfo1 + d.lfo2 + d.lfo3 + d.lfo4) * 0.25;
    d.pulse = d.lfo4;
    OutputBuffer[0] = d;
}
