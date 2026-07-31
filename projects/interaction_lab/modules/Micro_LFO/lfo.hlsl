// One continuity-safe scalar LFO.
// The persistent buffer is both state and publication: rate changes affect only
// future phase increments, so dragging Rate never rescales elapsed history.
RWStructuredBuffer<float4> LfoState : register(u0);

static const float TAU = 6.28318530718;
static const float MAGIC = 61403.0;

float waveBipolar(float p, uint shape) {
    p = frac(p);
    if (shape == 0u) return sin(p * TAU);
    if (shape == 1u) return 1.0 - 4.0 * abs(p - 0.5);
    if (shape == 2u) return p * 2.0 - 1.0;
    return p < 0.5 ? 1.0 : -1.0;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 s = LfoState[0];
    if (s.w != MAGIC || isnan(s.x)) s = float4(0.0, 0.5, 0.0, MAGIC);

    float dt = min(max(_DeltaTime, 0.0), 0.05);
    float phaseNow = frac(s.x + max(rate, 0.0) * dt);
    uint shapeNow = (uint)clamp(round(shape), 0.0, 3.0);
    float bipolarNow = waveBipolar(phaseNow, shapeNow) * saturate(depth);
    float valueNow = bipolarNow * 0.5 + 0.5;

    LfoState[0] = float4(phaseNow, valueNow, bipolarNow, MAGIC);
}
