// Resonance / echo - what came back. Reads EventIn0 ("Echo"), the records the Pulse Bus Script
// sent, once each:
//   NoteOn  a strike that was played - ring the bar, remember the note, time the round trip
//   Trigger a retune (the Script's scale or root changed) - relabel the bar, do not ring it
//
// Each record carries the Script's running sequence number, so a record handed over on more than
// one cook is applied once (the same rule as viewport events, and the same reset: a Script that
// restarts counts from zero again, which drops the watermark).
#include "../Pulse/pulse.hlsli"

StructuredBuffer<PbRec> W : register(t0);       // Pulse's World: its clock is in W_HEAD.d
RWStructuredBuffer<PbRec> B : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float now = W[W_HEAD].d;                         // Pulse's clock, not this node's _Time
    PbRec head = B[B_HEAD];
    uint n = min(_EventIn0_Count, 256u);
    uint lastSeq = head.e;
    uint maxSeq = 0u;
    [loop] for (uint i = 0u; i < n; i++) maxSeq = max(maxSeq, (uint)EventIn0[i].payload.w);
    if (n > 0u && maxSeq < lastSeq) lastSeq = 0u;          // the Script restarted
    uint newest = lastSeq;

    [loop] for (uint j = 0u; j < n; j++)
    {
        GPUEventInputRecord r = EventIn0[j];
        uint seq = (uint)r.payload.w;
        if (seq <= lastSeq) continue;
        newest = max(newest, seq);
        uint code = (uint)r.payload.x;
        uint bar = min(code >> 7, PB_BARS - 1u);
        uint note = code & 127u;
        PbRec b = B[bar];
        b.b.x = (float)note;
        b.f = 1u;
        if (r.event_type == PB_EV_NOTEON)
        {
            float vel = saturate(r.payload.y / 127.0);
            float trip = max(now - r.payload.z, 0.0) * 1000.0;       // strike stamp -> now
            b.a = float2(now, vel);
            b.c = trip;
            b.e += 1u;
            head.a.x += 1.0;
            head.a.y = (head.a.y <= 0.0) ? trip : lerp(head.a.y, trip, 0.15);
            PbRec h = (PbRec)0;
            h.a = float2(now, (float)bar);
            h.b = float2(r.payload.z, (float)note);
            h.c = vel;
            B[B_HIST0 + head.f % PB_HIST] = h;
            head.f += 1u;
        }
        else b.b.y = now;                                     // retune
        B[bar] = b;
    }
    head.e = newest;
    B[B_HEAD] = head;
}
