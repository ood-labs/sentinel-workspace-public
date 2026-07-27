struct DebtQuantum
{
    float2 position;
    float2 axis;
    float mass;
    float radius;
    uint kind;
    uint sourceIndex;
    uint ledgerId;
    uint active;
    float phase;
    float age;
};

struct LedgerStats
{
    float activeCount;
    float meanMass;
    float macroMass;
    float meanAxisAngle;
};

StructuredBuffer<DebtQuantum> DebtInput : register(t0);
RWStructuredBuffer<LedgerStats> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float activeCountValue = 0.0;
    float massSum = 0.0;
    float macroMassValue = 0.0;
    float2 axisSum = float2(0.0, 0.0);

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        DebtQuantum quantum = DebtInput[i];
        if (quantum.active == 0u) continue;

        activeCountValue += 1.0;
        massSum += quantum.mass;
        macroMassValue += quantum.kind == 1u ? quantum.mass : 0.0;
        axisSum += quantum.axis * max(quantum.mass, 0.05);
    }

    LedgerStats stats;
    stats.activeCount = activeCountValue;
    stats.meanMass = activeCountValue > 0.0 ? massSum / activeCountValue : 0.0;
    stats.macroMass = macroMassValue;
    stats.meanAxisAngle = length(axisSum) > 1e-5 ? atan2(axisSum.y, axisSum.x) : 0.0;
    OutputBuffer[0] = stats;
}
