// LFO Compute — evaluate 4 waveforms and write to structured buffer
// Shapes: 0=Sine, 1=Triangle, 2=Saw, 3=Square
// Output range: [0, amplitude]

struct LFOData {
    float lfo1;
    float lfo2;
    float lfo3;
    float lfo4;
};

RWStructuredBuffer<LFOData> OutputBuffer : register(u0);

#define PI 3.14159265

float evalLFO(float t, float spd, float amp, float shapeF)
{
    float phase = t * spd;
    float p = frac(phase);
    float raw = 0.0;
    if (shapeF < 0.5) raw = sin(phase * 2.0 * PI) * 0.5 + 0.5;
    else if (shapeF < 1.5) raw = 1.0 - abs(p * 2.0 - 1.0);
    else if (shapeF < 2.5) raw = p;
    else raw = step(0.5, p);
    return raw * amp;
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float t = _Time;
    LFOData d;
    d.lfo1 = evalLFO(t, lfo1_speed, lfo1_amp, lfo1_shape);
    d.lfo2 = evalLFO(t, lfo2_speed, lfo2_amp, lfo2_shape);
    d.lfo3 = evalLFO(t, lfo3_speed, lfo3_amp, lfo3_shape);
    d.lfo4 = evalLFO(t, lfo4_speed, lfo4_amp, lfo4_shape);
    OutputBuffer[0] = d;
}
