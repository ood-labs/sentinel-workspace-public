// FM_Colony / hist.hlsl — the gait history ring for the focused ant.
//
// One sample every `gait_rate` seconds, recording which of the six legs were bearing weight.
// This is the data behind the Hildebrand footfall chart, which is the readout the renderer
// cannot give: a still frame of an ant shows six legs in some arrangement and says nothing at
// all about whether the two tripods are actually anti-phase or whether a foot is scuffing.
//
// The pass that owns the ring owns its cursor. Element 0 is the header — `t` is the write
// cursor and `bits` the number of samples written. Deriving the cursor in the consumer from a
// shared clock does not work: the two passes observe that clock a cook apart and the reader
// lands on the slot that is about to be overwritten.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWStructuredBuffer<FmGait> Hist : register(u0);
StructuredBuffer<FmCtl>  Ctl  : register(t1);
StructuredBuffer<FmAnt>  Ants : register(t2);
StructuredBuffer<FmFoot> Feet : register(t3);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    FmGait hdr = Hist[0];
    FmCtl ctl = Ctl[0];

    if (!(abs(hdr.t) < 1e9) || ctl.rebuild > 0.5) { hdr = (FmGait)0; }

    uint cursor = (uint)max(hdr.t, 0.0) % FM_GAIT_HIST;
    float written = hdr.bits;

    float interval = max(gait_rate, 0.004);
    // hdr.slip doubles as "time of the last sample". Named for what the field carries in the
    // sample records rather than in the header, which is the cost of one shared struct; the
    // alternative is a second 32-byte buffer for one float.
    if (ctl.time - hdr.slip < interval) { Hist[0] = hdr; return; }
    hdr.slip = ctl.time;

    uint ai = min((uint)focus_ant, FM_MAX_ANTS - 1u);
    FmAnt a = Ants[ai];

    uint bits = 0u;
    float worst = 0.0;
    for (uint lg = 0u; lg < FM_LEGS; lg++)
    {
        FmFoot f = Feet[ai * FM_LEGS + lg];
        if (f.stance > 0.5) bits |= (1u << lg);
        worst = max(worst, f.slip);
    }

    FmGait s;
    s.t = ctl.time;
    // Stored as a plain NUMBER, not as asfloat(bits).
    //
    // A six-leg mask is 0..63, and asfloat of a small integer is a DENORMAL — which D3D
    // flushes to zero by default. Every sample therefore came back as "no legs down" and the
    // chart drew nothing at all, while the speed trace beside it worked perfectly, because that
    // field is an ordinary float. Values 0..63 are exactly representable, so a round trip
    // through float and back is lossless.
    s.bits = (float)bits;
    s.slip = worst;
    s.speed = a.speed;
    s.turn = a.turn;
    s.lp0 = frac(a.gait);
    s.pad0 = a.task;
    s.pad1 = 0.0;

    Hist[1u + cursor] = s;

    hdr.t = (float)((cursor + 1u) % FM_GAIT_HIST);
    hdr.bits = min(written + 1.0, (float)FM_GAIT_HIST);
    Hist[0] = hdr;
}
