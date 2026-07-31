RWStructuredBuffer<float4> SequenceState : register(u0);

static const float MAGIC = 84117.0;

float enabledAt(uint i) {
    if (i == 0u) return step_1 ? 1.0 : 0.0;
    if (i == 1u) return step_2 ? 1.0 : 0.0;
    if (i == 2u) return step_3 ? 1.0 : 0.0;
    if (i == 3u) return step_4 ? 1.0 : 0.0;
    if (i == 4u) return step_5 ? 1.0 : 0.0;
    if (i == 5u) return step_6 ? 1.0 : 0.0;
    if (i == 6u) return step_7 ? 1.0 : 0.0;
    return step_8 ? 1.0 : 0.0;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 s = SequenceState[0];
    float4 meta = SequenceState[1];
    if (meta.w != MAGIC || isnan(s.x)) {
        s = float4(0.0, enabledAt(0u), 0.0, 0.0);
        meta = float4(0.0, 0.0, 0.0, MAGIC);
    }

    float dt = min(max(_DeltaTime, 0.0), 0.05);
    uint previousStep = (uint)clamp(floor(frac(s.x) * 8.0), 0.0, 7.0);
    float phaseNow = frac(s.x + max(rate, 0.0) * dt / 8.0);
    uint currentStep = (uint)clamp(floor(phaseNow * 8.0), 0.0, 7.0);
    float count = s.w + (currentStep != previousStep ? 1.0 : 0.0);

    SequenceState[0] = float4(phaseNow, enabledAt(currentStep), (float)currentStep, count);
    SequenceState[1] = meta;
}
