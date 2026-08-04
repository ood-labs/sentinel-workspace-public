// TP_Sim / ctl.hlsl — reduce the event queue ONCE, single-threaded, into a small state buffer.
//
// This is the recommended shape for an events module and it matters more here than usual: the
// wave passes run 65536 threads three times per cook, and every one of them needs the same
// answer to "where was the pointer, where is it now, and how much time passed". Deciding that
// once in one thread is both cheaper and the only way to make it consistent.
//
// It also owns the CLOCK. Source phases integrate dtEff here rather than reading _Time, so the
// whole surface is driven from one accumulator that a reset can zero — and so the sim keeps
// real-time behaviour at any cook rate.
#include "sim.hlsli"

RWStructuredBuffer<TpCtl> Ctl : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    TpCtl st = Ctl[0];
    TpCtl mem = Ctl[1];

    // A cook rate of two thousand per second is normal for a light module, so a per-cook
    // constant would be meaningless here. Everything below is in seconds.
    float dt = clamp(_DeltaTime, 0.0, 0.05);

    if (st.a.x < 0.5)
    {
        st = (TpCtl)0;
        mem = (TpCtl)0;
        st.a.x = 1.0;
    }

    bool reset = (sim_reset > 0.5);
    if (reset) { st.a.y = 0.0; }

    st.a.y += dt * max(time_scale, 0.0);
    st.a.z = dt * max(time_scale, 0.0);
    st.a.w += 1.0;

    // --- internal pointer: this module's own preview, which shows the surface full-bleed, so
    // a pointer position IS a simulation uv with no remapping at all.
    float2 lastIn = mem.a.xy;
    bool haveLastIn = mem.b.x > 0.5;
    float2 curIn = lastIn;
    bool inDrag = false;
    bool inClick = false;
    float2 clickAt = float2(0.5, 0.5);

    uint n = min((uint)_ViewportEventCount, 64u);
    for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];
        if (ev.type == 5u)
        {
            if (ev.code == 3u)                                  // drag
            {
                if (ev.phase == 5u) { curIn = ev.position; lastIn = ev.position; haveLastIn = true; inDrag = true; }
                else if (ev.phase == 6u) { curIn = ev.position; inDrag = true; }
                else { inDrag = false; haveLastIn = false; }    // end / cancel
            }
            else if (ev.code == 1u && ev.phase == 7u)           // click: one drop, right there
            {
                inClick = true; clickAt = ev.position;
            }
        }
    }

    st.b = float4(haveLastIn ? lastIn : curIn, curIn);
    st.d.x = inDrag ? 1.0 : 0.0;
    st.d.z = inClick ? 1.0 : 0.0;
    mem.a.xy = curIn;
    mem.b.x = inDrag ? 1.0 : 0.0;

    // --- external pointer: driven by expression from TP_Render's pick control outputs, so a
    // drag across the BEAUTY image lands here. One frame behind, which for water is nothing.
    float2 curEx = float2(saturate(ext_u), saturate(ext_v));
    bool exOn = (ext_down > 0.5);
    float2 lastEx = (mem.b.y > 0.5) ? mem.a.zw : curEx;

    st.c = float4(lastEx, curEx);
    st.d.y = exOn ? 1.0 : 0.0;
    st.d.w = reset ? 1.0 : 0.0;
    mem.a.zw = curEx;
    mem.b.y = exOn ? 1.0 : 0.0;

    // The impulse position gets its own slot rather than sharing the drag segment's: a click
    // arriving in the same cook as a drag update would otherwise overwrite the stroke.
    mem.b.z = clickAt.x;
    mem.b.w = clickAt.y;

    Ctl[0] = st;
    Ctl[1] = mem;
}
