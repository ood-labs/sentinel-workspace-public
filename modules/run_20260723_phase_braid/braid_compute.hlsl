struct BraidData
{
    float loom_phase;
    float gate_phase;
    float memory_phase;
    float energy;
};

RWStructuredBuffer<BraidData> OutputBuffer : register(u0);

float pb_wrap(float x)
{
    return frac(x);
}

float pb_fold(float x)
{
    return abs(frac(x) - 0.5) * 2.0;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float p = pb_wrap(_Tex0.Load(int3(0, 0, 0)).r);
    float wave = sin(p * 6.28318530718);

    BraidData values;
    values.loom_phase = p;

    if (braid_mode == 1)
    {
        values.gate_phase = pb_wrap(p + gate_offset);
        values.memory_phase = pb_wrap(p + memory_offset);
    }
    else if (braid_mode == 2)
    {
        values.gate_phase = pb_fold(p * gate_ratio + gate_offset);
        values.memory_phase = pb_wrap(1.0 - p + memory_offset + wave * memory_lag * 0.25);
    }
    else
    {
        values.gate_phase = pb_wrap(p * gate_ratio + gate_offset + wave * crossmod * 0.08);
        values.memory_phase = pb_wrap(p - wave * memory_lag + memory_offset);
    }

    float arch = saturate(sin(p * 3.14159265359));
    values.energy = pow(arch * arch, max(energy_shape, 0.05));
    OutputBuffer[0] = values;
}
