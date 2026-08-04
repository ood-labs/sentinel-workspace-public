// TP_Scope / tick.hlsl — the clock, the parity, and the trail write gate.
//
// Decided once, single threaded, for the same reason every other node in this show does it: the
// scatter runs thousands of threads that all need the same answer to "which half am I filling"
// and "is this the cook that records a trail sample".
#include "scope.hlsli"

RWStructuredBuffer<TpSCtl> Ctl : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    TpSCtl st = Ctl[0];

    float dt = clamp(_DeltaTime, 0.0, 0.05);

    if (st.a.x < 0.5)
    {
        st = (TpSCtl)0;
        st.a.x = 1.0;
    }

    st.a.y += dt;
    st.a.z = dt;
    st.a.w += 1.0;

    // THE TRAIL GATE. Recording every cook would fill a 64-sample ring in about a second at
    // 60Hz, so the trail would reach barely a body length behind the fish. Accumulating elapsed
    // time and advancing the head only when the interval passes decouples how far the trail
    // reaches from how fast the node happens to be cooking.
    st.b.y += dt;
    if (st.b.y >= max(trail_rate, 0.005))
    {
        st.b.y = 0.0;
        st.b.x = fmod(st.b.x + 1.0, (float)TP_TRAIL);
    }

    Ctl[0] = st;
}
