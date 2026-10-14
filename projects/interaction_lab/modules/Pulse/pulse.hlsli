// Pulse Bus - shared layout: the tuned bars, the record buffers, the event payloads.
//
// The stage is a glockenspiel turned into a marble run: twelve bars on two staircases that meet
// in a V, lowest (longest) at the bottom. A ball rolls off the low end of one bar onto the next,
// so a drop plays a falling run. Every strike leaves the GPU (Pulse) as an Impact event; the
// Pulse Bus Script decides the note, plays it on MIDI Out and echoes it on to Resonance, which
// rings the bars it played over Pulse's image. Shared by both modules.
//
// Authored in DESIGN pixels of the 1280x720 frame, y down.
#ifndef PULSE_HLSLI
#define PULSE_HLSLI

#define PB_W        1280.0
#define PB_H        720.0
#define PB_BALLS    64u
#define PB_BARS     12u
#define PB_SUB      4u          // physics substeps per cook
#define PB_HIST     64u         // scope history per direction
#define PB_BALL_R   9.0
#define PB_BAR_T    5.0         // bar half thickness

// Event payloads (four floats each; event_type is the Script ABI's: Trigger 1, NoteOn 2, Impact 5)
//   out  Impact  (bar, normal speed px/s, contact along the bar 0..1, stamp = sim time s)
//   in   NoteOn  (bar * 128 + note, velocity 0..127, stamp of the strike it answers, seq)
//   in   Trigger (bar * 128 + note, 0, -1, seq) - a retune: label the bar, do not ring it
#define PB_EV_TRIGGER 1u
#define PB_EV_NOTEON  2u
#define PB_EV_IMPACT  5u

// One 32-byte record type, read by role (named accessors below keep the passes legible).
struct PbRec { float2 a; float2 b; float c; float d; uint e; uint f; };

// ---- world (written by `sim`)
//   W_HEAD   a = (auto phase s, last pour time), b = last pointer (design px), c = spawn count,
//            d = Pulse's clock (its _Time this cook), e = last viewport event sequence,
//            f = flags (bit0 auto, bit1 Space held)
//   Every module's _Time is its own (it accumulates from when that node started), so a stamp
//   only means something in the clock that wrote it. Strike stamps are Pulse's; a downstream
//   node that times them reads Pulse's "now" from W_HEAD.d instead of its own _Time.
//   W_STATS  c = impacts total (float, exact), e = history write index
//   balls    a = position, b = velocity, c = radius (0 = free slot), d = age s, e = id
//   sparks   a = (strike time, along), b = (speed, ball id)            one per bar
//   history  a = (strike time, bar), b = (speed, along)                ring of PB_HIST
#define W_HEAD   0u
#define W_STATS  1u
#define W_BALL0  2u
#define W_SPARK0 (W_BALL0 + PB_BALLS)
#define W_HIST0  (W_SPARK0 + PB_BARS)
#define W_COUNT  (W_HIST0 + PB_HIST)

// ---- bars (Resonance: written by its `echo` pass from the Script's records)
//   per bar  a = (ring time, velocity 0..1), b = (note, retune time), c = round trip ms,
//            e = echoes, f = 1 once a note is known
//   B_HEAD   a = (echoes total, round trip ms smoothed), e = last echo seq, f = history write index
//   history  a = (echo time, bar), b = (strike stamp, note), c = velocity 0..1
#define B_HEAD   PB_BARS
#define B_HIST0  (PB_BARS + 1u)
#define B_COUNT  (B_HIST0 + PB_HIST)

// Bar i (0 = lowest pitch): centre, unit direction pointing down the slope (toward the V),
// and half length. Lengths follow a real glockenspiel loosely: lower is longer.
void pbBar(uint i, out float2 c, out float2 dir, out float halfLen)
{
    uint rank = (PB_BARS - 1u) - min(i, PB_BARS - 1u);     // 0 = top left, the highest bar
    float k = (float)(rank >> 1);                            // step down the staircase, 0..5
    bool right = (rank & 1u) != 0u;
    float ang = radians(9.0 + 0.6 * k);                      // a little steeper toward the bottom
    float x = 170.0 + k * 62.0;
    c = float2(right ? PB_W - x : x, 116.0 + k * 84.0);
    dir = float2(right ? -cos(ang) : cos(ang), sin(ang));
    halfLen = 0.5 * (96.0 + (float)rank * 11.5);
}
// The free-free bar's first bending mode, normalised to 1 at the ends (|u| = 1). Its nodes sit at
// 0.224 and 0.776 of the length - where a real glockenspiel bar is pinned.
float pbMode(float u)
{
    const float beta = 4.7300, sigma = 0.9825;
    float x = beta * saturate(0.5 + 0.5 * u);
    float phi = cosh(x) + cos(x) - sigma * (sinh(x) + sin(x));
    return phi * 0.5;
}
#define PB_NODE 0.552           // pins: |u| at the nodes, as a fraction of the half length

float2 pbFromUv(float2 uv) { return uv * float2(PB_W, PB_H); }

#endif
