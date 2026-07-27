struct BreathState
{
    float breath_phase;
    float asymmetry_phase;
    float rupture_phase;
    float drift_phase;
    float valid;
    float eclipse_phase;
    float pad1;
    float pad2;
};

StructuredBuffer<BreathState> Current : register(t0);
RWStructuredBuffer<BreathState> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    OutputBuffer[0] = Current[0];
}
