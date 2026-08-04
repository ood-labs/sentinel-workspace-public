// TP_Caustics / tick.hlsl — a cook counter.
//
// The accumulator needs to know which half of itself to fill this cook and which half to wipe
// for the next one, and there is no frame index in the injected preamble — only _Time and
// _DeltaTime, neither of which can be trusted to change by exactly one unit per cook.
RWStructuredBuffer<float4> Tick : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float4 t = Tick[0];
    t.x = (t.x < 0.0 || t.x > 1e9) ? 0.0 : t.x + 1.0;
    Tick[0] = t;
}
