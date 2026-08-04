// TP_School / ctl.hlsl — the clock, decided once.
//
// The swim pass integrates dt, it does not read _Time. A light module can cook at thousands of
// hertz, so a per-cook constant would be meaningless, and an accumulator is also the only thing
// a Reset can actually zero.
#include "school.hlsli"

RWStructuredBuffer<TpSCtl> Ctl : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    TpSCtl st = Ctl[0];

    // Clamped: a stalled frame must not teleport the school across the tank in one step, which
    // would launch every fish through the glass and leave the flocking terms to sort it out.
    float dt = clamp(_DeltaTime, 0.0, 0.05);

    if (st.a.x < 0.5)
    {
        st = (TpSCtl)0;
        st.a.x = 1.0;
    }

    if (sim_reset > 0.5)
    {
        st.a.x = 0.0;          // the swim pass re-seeds the whole school on this
        st.a.y = 0.0;
    }

    st.a.y += dt;
    st.a.z = dt;
    st.a.w += 1.0;

    // Advance the trail ring on a real time interval rather than per cook. A light module can
    // cook far faster than 60Hz, and a per-cook ring would hold a fraction of a second of
    // history — a trail barely longer than the fish drawing it.
    st.b.y += dt;
    if (st.b.y >= max(trail_rate, 0.005))
    {
        st.b.y = 0.0;
        st.b.x = fmod(st.b.x + 1.0, (float)TP_TRAIL);
    }

    Ctl[0] = st;
}
