struct PhaseState
{
    float phase_periods;
    float running;
    float speed;
    float reserved;
};

struct SignalSample
{
    float sample_index;
    float sample_u;
    float value;
    float active;
};

StructuredBuffer<PhaseState> Phase : register(t0);
RWStructuredBuffer<SignalSample> OutputBuffer : register(u0);

float tdHermiteNoise(float x, float seedValue)
{
    float cell = floor(x);
    float local = frac(x);
    float smoothLocal = local * local * (3.0 - 2.0 * local);
    float a = hash11(cell + seedValue * 101.317) * 2.0 - 1.0;
    float b = hash11(cell + 1.0 + seedValue * 101.317) * 2.0 - 1.0;
    return lerp(a, b, smoothLocal);
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint index = tid.x;
    if (index >= 128u)
        return;

    float u = (float)index / 127.0;
    float safePeriod = max(period_seconds, 0.001);
    float seconds = (float)index / 60.0;
    float baseX = seconds * 2.0 / safePeriod + Phase[0].phase_periods * 2.0;

    float weighted = 0.0;
    float weightSum = 0.0;
    float frequency = 1.0;
    float weight = 1.0;

    [unroll]
    for (int octave = 0; octave < 5; ++octave)
    {
        if (octave <= harmonics)
        {
            float octaveSeed = (float)seed + (float)octave * 17.0;
            weighted += tdHermiteNoise(baseX * frequency, octaveSeed) * weight;
            weightSum += weight;
        }
        frequency *= 2.0;
        weight *= roughness;
    }

    float normalized = weighted / max(weightSum, 0.0001);
    normalized = sign(normalized) * pow(abs(normalized), max(exponent, 0.001));

    SignalSample outRec;
    outRec.sample_index = (float)index;
    outRec.sample_u = u;
    outRec.value = offset + normalized * amplitude * 0.5;
    outRec.active = 1.0;
    OutputBuffer[index] = outRec;
}
