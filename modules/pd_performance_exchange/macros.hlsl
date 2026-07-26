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

struct ExchangeState
{
    float2 focus;
    float divergence;
    float cameraFollow;
    float printPressure;
    float marginCall;
    float activeDebt;
    float macroMass;
    float generation;
    float initialized;
    float owner;
    float pad;
};

StructuredBuffer<ExchangeState> PreviousState : register(t1);
StructuredBuffer<DebtQuantum> DebtInput : register(t2);
RWStructuredBuffer<ExchangeState> OutputState : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float4 spatial = _Tex0.Load(int3(0, 0, 0));
    float4 performance = _Tex0.Load(int3(1, 0, 0));
    float4 capture = _Tex0.Load(int3(2, 0, 0));

    ExchangeState state = PreviousState[0];
    state.focus = spatial.xy;
    state.divergence = spatial.z;
    state.cameraFollow = spatial.w;
    state.printPressure = performance.x;
    state.marginCall = performance.y;
    state.generation = performance.z;
    state.initialized = performance.w;
    state.owner = capture.x;
    state.pad = capture.y;

    float activeDebt = 0.0;
    float macroMass = 0.0;
    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        DebtQuantum quantum = DebtInput[i];
        if (quantum.active == 0u) continue;
        activeDebt += 1.0;
        if (quantum.kind == 1u) macroMass += quantum.mass;
    }
    state.activeDebt = activeDebt;
    state.macroMass = macroMass;

    OutputState[0] = state;
}
