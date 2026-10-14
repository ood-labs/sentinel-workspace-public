// Pattern - the pattern's records, the editor's panes, and the hit tests every pass shares (the reducer
// hits exactly what the layout pass draws).
//
// A polymetric step sequencer: six lanes on one sixteenth-note clock, each its own length (1-16 steps),
// so they drift against each other and line up again only every LCM(lengths) steps. A step is on or
// off, with a velocity, a chance, a ratchet (1-4 hits inside the step) and a nudge (-0.5..+0.5 step).
// Swing delays every second sixteenth. A lane plays its step (k - turn) mod length at global step k.
//
// Saved records (the first PT_SAVED: the project, node presets and undo carry them):
//   0  P0   (tempo bpm, swing 0.5..0.75, -, -)
//   1  PM   (PT_MAGIC, -, -, -)
//   2 + lane            LA  (length 1..16, turn 0..15, note 0..127, mute 1 + solo 2)
//   8 + lane            LB  (hits: the Euclid count last spread, -, -, -)
//   14 + lane * 16 + i  ST  (on 0|1 + 2 * (ratchet - 1), velocity 0..1, chance 0..1, nudge -0.5..0.5)
// Working state after them (never saved, never restored):
//   110 V0  (playing 0|1, now: whole step, now: fraction, working magic)  <- control outputs read this
//   111 V1  (event watermark low 16 bits, high 16 bits, drag mode, drag target)
//   112 V2  (press x px, press y px, last drag x px, last drag y px)
//   113 V3  (selected lane, selected step, edit layer, paint value)
//   114 V4  (sent up to: whole step, fraction; history head; cooks)
//   115 V5  the drag's origin (meaning per mode)
//   116 V6  (grid | rings split, upper | tape split, Space held 0|1, -)
//   117 V7  the lanes' hit envelopes 1-4 (0..1, decaying)               <- control outputs
//   118 V8  (envelope 5, envelope 6, hits per second, -)                 <- control outputs
//   119..246 history: 128 hits sent (step whole, offset in steps from it, lane + 8 * flags, velocity)
//   247..356 the undo snapshot of 0..109 - also every drag's origin ("snapshot + delta")
//   357 U0  (1 when a snapshot exists)
//
// Every hit goes out on EventOut "Hits" PT_LOOKAHEAD seconds before it is due, once:
//   event_type PT_EV_HIT, payload (lane * 128 + note, velocity 1..127, due in seconds, ratchet index)
// so whatever schedules it (the Pattern Bus script, then MIDI Out) can place it exactly, however the
// frames fall.
#ifndef PT_HLSLI
#define PT_HLSLI

#ifdef PT_STATE_RW
RWStructuredBuffer<float4> S : register(u0);
#else
StructuredBuffer<float4> S : register(t0);
#endif

#define PT_LANES   6u
#define PT_STEPS   16u
#define PT_P0      0u
#define PT_PM      1u
#define PT_LA0     2u
#define PT_LB0     8u
#define PT_ST0     14u
#define PT_SAVED   110u
#define PT_V0      110u
#define PT_V1      111u
#define PT_V2      112u
#define PT_V3      113u
#define PT_V4      114u
#define PT_V5      115u
#define PT_V6      116u
#define PT_V7      117u
#define PT_V8      118u
#define PT_HIST0   119u
#define PT_HISTN   128u
#define PT_UNDO0   247u
#define PT_U0      357u
#define PT_COUNT   358u
#define PT_MAGIC   2112.0
#define PT_VMAGIC  21212.0

#define PT_LOOKAHEAD 0.10            // seconds a hit is sent before it is due
#define PT_EV_HIT    9u               // the Hits event type

// history flags (record .z = lane + 8 * flags)
#define PT_H_PLAYED  1u
#define PT_H_DROPPED 2u              // its chance said no
#define PT_H_RATCHET 4u              // a ratchet's later hit

// edit layers (V3.z): what a drag across the grid paints
#define PT_E_STEPS   0u
#define PT_E_VEL     1u
#define PT_E_CHANCE  2u
#define PT_E_RATCHET 3u
#define PT_E_NUDGE   4u

// drag modes (V1.z)
#define DM_NONE   0u
#define DM_PAINT  1u                 // across a lane's cells: the edit layer
#define DM_LEN    2u                 // a lane's end bracket: its length
#define DM_RING   3u                 // a ring: turn the lane
#define DM_FIELD  4u                 // an inspector field (target = PT_F_*)
#define DM_SPLITX 5u                 // the grid | rings splitter
#define DM_SPLITY 6u                 // the upper | tape splitter

// inspector fields
#define PT_F_NOTE   0u
#define PT_F_LEN    1u
#define PT_F_TURN   2u
#define PT_F_HITS   3u
#define PT_F_VEL    4u
#define PT_F_CHANCE 5u
#define PT_F_NUDGE  6u
#define PT_F_BPM    7u
#define PT_F_SWING  8u

// ---------------------------------------------------------------- the records
float  ptBpm()   { return clamp(S[PT_P0].x, 30.0, 300.0); }
float  ptSwing() { return clamp(S[PT_P0].y, 0.5, 0.75); }
float  ptStepsPerSec() { return ptBpm() / 60.0 * 4.0; }
uint   ptLen(uint l)  { return clamp((uint)S[PT_LA0 + l].x, 1u, PT_STEPS); }
uint   ptTurn(uint l) { return ((uint)S[PT_LA0 + l].y) % ptLen(l); }
uint   ptNote(uint l) { return min((uint)S[PT_LA0 + l].z, 127u); }
bool   ptMute(uint l) { return (((uint)S[PT_LA0 + l].w) & 1u) != 0u; }
bool   ptSolo(uint l) { return (((uint)S[PT_LA0 + l].w) & 2u) != 0u; }
uint   ptHits(uint l) { return min((uint)S[PT_LB0 + l].x, ptLen(l)); }
uint   ptStepSlot(uint l, uint i) { return PT_ST0 + l * PT_STEPS + i; }
float4 ptStep(uint l, uint i) { return S[ptStepSlot(l, i)]; }
bool   ptOn(float4 st) { return (((uint)st.x) & 1u) != 0u; }
uint   ptRatchet(float4 st) { return 1u + min((uint)(st.x * 0.5), 3u); }
float4 ptMakeStep(bool on, uint ratchet, float vel, float chance, float nudge)
{
    return float4((on ? 1.0 : 0.0) + 2.0 * (float)(clamp(ratchet, 1u, 4u) - 1u), saturate(vel), saturate(chance), clamp(nudge, -0.5, 0.5));
}
float4 ptWithOn(float4 st, bool on) { return ptMakeStep(on, ptRatchet(st), st.y, st.z, st.w); }
float4 ptWithRatchet(float4 st, uint r) { return ptMakeStep(ptOn(st), r, st.y, st.z, st.w); }

bool ptAnySolo()
{
    bool any = false;
    [unroll] for (uint l = 0u; l < PT_LANES; l++) any = any || ptSolo(l);
    return any;
}
bool ptAudible(uint l, bool anySolo) { return !ptMute(l) && (!anySolo || ptSolo(l)); }

// the lane's step at global step k (a whole number below 2^24). In integers, never fmod: FXC makes
// fmod(x, y) frac(x / y) * y, and x / y is a few 1e-5 out by k ~ 3,000, so a 3.99997 truncates to
// the step before - which then plays twice, in the step after's place.
uint ptLaneStep(uint l, float k)
{
    uint n = ptLen(l);
    return ((uint)max(k, 0.0) % n + n - ptTurn(l)) % n;
}
// where the lane's cycle stands at a fractional global position, 0..len (its ring hand)
float ptLanePos(uint l, float whole, float frac)
{
    return (float)((uint)max(whole, 0.0) % ptLen(l)) + frac;
}

// k hits spread evenly over n steps (a rotation of Bjorklund's Euclidean rhythm)
bool ptEuclid(uint i, uint k, uint n) { return n > 0u && ((i * k) % n) < k; }

uint ptGcd(uint a, uint b)
{
    [loop] for (uint it = 0u; it < 32u && b != 0u; it++) { uint t = a % b; a = b; b = t; }
    return max(a, 1u);
}
// how many steps until every lane's cycle starts together again
uint ptLcm()
{
    uint m = 1u;
    [unroll] for (uint l = 0u; l < PT_LANES; l++) { uint n = ptLen(l); m = m / ptGcd(m, n) * n; }
    return m;
}

// an integer hash for the chance roll: the same step of the same pass always rolls the same
float ptRoll(uint lane, float k, uint r)
{
    uint h = (uint)k * 747796405u + lane * 2891336453u + r * 277803737u + 0x9E3779B9u;
    h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
    h = (h >> 22u) ^ h;
    return (float)(h & 0xFFFFFFu) / 16777216.0;
}

// ---------------------------------------------------------------- panes
struct PtLayout
{
    float4 head, hint, block, inner;
    float4 tools;                    // the edit layer, the transport
    float4 upper;                    // the grid and the rings, over the inspectors
    float4 gridArea, laneCol, cells, ruler;
    float4 ringArea; float2 ringC; float ringR, ringR0;
    float4 gripX; float splitXAt;
    float4 laneI, stepI;
    float4 gripY; float splitYAt;
    float4 tape;
    float  rowH, colW;
};

#define PT_GAP 14.0

PtLayout ptLayout(float2 res, float s, float2 split)
{
    PtLayout L;
    float m = 16.0 * s;
    L.head = float4(m, 14.0 * s, res.x - m, 44.0 * s);
    L.hint = float4(m, res.y - 41.0 * s, res.x - m, res.y - 11.0 * s);
    L.block = float4(m, 54.0 * s, res.x - m, L.hint.y - 10.0 * s);
    L.inner = ilInset(L.block, 12.0 * s);
    L.tools = float4(L.inner.x, L.inner.y, L.inner.z, L.inner.y + 30.0 * s);
    float4 rest = float4(L.inner.x, L.tools.w + 12.0 * s, L.inner.z, L.inner.w);
    ILSplit sy = ilSplitY(rest, split.y, 380.0 * s, 120.0 * s, PT_GAP * s, 7.0 * s);
    L.gripY = sy.grip;
    L.splitYAt = sy.at;
    L.tape = sy.b;
    float4 a = sy.a;
    float4 insp = float4(a.x, a.w - 118.0 * s, a.z, a.w);
    L.upper = float4(a.x, a.y, a.z, insp.y - PT_GAP * s);
    ILSplit sx = ilSplitX(L.upper, split.x, 560.0 * s, 280.0 * s, PT_GAP * s, 7.0 * s);
    L.gripX = sx.grip;
    L.splitXAt = sx.at;
    L.gridArea = sx.a;
    L.ringArea = sx.b;
    L.laneI = float4(insp.x, insp.y, L.gridArea.z, insp.w);
    L.stepI = float4(L.ringArea.x, insp.y, insp.z, insp.w);
    // the grid: a header column for the lanes, a ruler of step numbers, sixteen columns
    float4 g = float4(L.gridArea.x, L.gridArea.y + 24.0 * s, L.gridArea.z, L.gridArea.w);
    L.laneCol = float4(g.x, g.y, g.x + 132.0 * s, g.w);
    L.cells = float4(L.laneCol.z + 10.0 * s, g.y + 22.0 * s, g.z - 18.0 * s, g.w);
    L.ruler = float4(L.cells.x, g.y, L.cells.z, g.y + 20.0 * s);
    L.rowH = clamp((L.cells.w - L.cells.y) / (float)PT_LANES, 26.0 * s, 64.0 * s);
    L.colW = (L.cells.z - L.cells.x) / (float)PT_STEPS;
    // the rings: a square in the right pane, a ring per lane (the first outermost)
    float4 ra = float4(L.ringArea.x, L.ringArea.y + 24.0 * s, L.ringArea.z, L.ringArea.w);
    float side = min(ra.z - ra.x, ra.w - ra.y);
    L.ringC = ilMid(ra);
    L.ringR = 0.5 * side - 10.0 * s;
    L.ringR0 = L.ringR * 0.34;
    return L;
}

// ---------------------------------------------------------------- the grid
float4 ptRow(PtLayout L, uint l) { float y = L.cells.y + l * L.rowH; return float4(L.laneCol.x, y, L.cells.z, y + L.rowH); }
float4 ptCell(PtLayout L, uint l, uint i, float s)
{
    float y = L.cells.y + l * L.rowH, x = L.cells.x + i * L.colW;
    return float4(x + 1.5 * s, y + 3.0 * s, x + L.colW - 1.5 * s, y + L.rowH - 3.0 * s);
}
// the lane and column under p in the cells area (x >= 16 when outside), or 0xFFFF
uint2 ptCellAt(PtLayout L, float2 p)
{
    if (p.x < L.cells.x || p.x >= L.cells.z || p.y < L.cells.y || p.y >= L.cells.y + PT_LANES * L.rowH) return uint2(0xFFFFu, 0xFFFFu);
    return uint2(min((uint)((p.y - L.cells.y) / L.rowH), PT_LANES - 1u), min((uint)((p.x - L.cells.x) / L.colW), PT_STEPS - 1u));
}
// a lane's end bracket, at the right edge of its last step
float2 ptBracket(PtLayout L, uint l) { return float2(L.cells.x + ptLen(l) * L.colW, ilMid(ptRow(L, l)).y); }
bool ptHitBracket(PtLayout L, uint l, float2 p, float s)
{
    float4 r = ptRow(L, l);
    return abs(p.x - ptBracket(L, l).x) < 6.0 * s && p.y >= r.y && p.y < r.w;
}
// the value a drag paints, from the pointer's height in the lane's row
float ptRowValue(PtLayout L, uint l, float y, float s)
{
    float4 c = ptCell(L, l, 0u, s);
    return saturate((c.w - y) / max(c.w - c.y, 1.0));
}
// the lane header's mute / solo chips
float4 ptMuteChip(PtLayout L, uint l, float s) { float4 r = ptRow(L, l); float y = ilMid(r).y; return float4(r.x + 82.0 * s, y - 9.0 * s, r.x + 102.0 * s, y + 9.0 * s); }
float4 ptSoloChip(PtLayout L, uint l, float s) { float4 c = ptMuteChip(L, l, s); return float4(c.z + 4.0 * s, c.y, c.z + 24.0 * s, c.w); }

// ---------------------------------------------------------------- the rings
float ptRingRad(PtLayout L, uint l) { return L.ringR - ((float)l + 0.5) * (L.ringR - L.ringR0) / (float)PT_LANES; }
float ptRingW(PtLayout L) { return (L.ringR - L.ringR0) / (float)PT_LANES; }
// a step's angle on its ring (radians clockwise from 12 o'clock): where the hand is when it plays
float ptStepAngle(uint l, uint i) { uint n = ptLen(l); return 6.2831853 * (float)((i + ptTurn(l)) % n) / (float)n; }
float2 ptRingPoint(PtLayout L, float r, float a) { return L.ringC + r * float2(sin(a), -cos(a)); }
// the lane whose ring band p is in, or 0xFFFF
uint ptRingAt(PtLayout L, float2 p)
{
    float d = length(p - L.ringC);
    if (d < L.ringR0 || d >= L.ringR) return 0xFFFFu;
    return min((uint)((L.ringR - d) / ptRingW(L)), PT_LANES - 1u);
}
float ptAngleAt(PtLayout L, float2 p) { float2 d = p - L.ringC; float a = atan2(d.x, -d.y); return a < 0.0 ? a + 6.2831853 : a; }
// the step dot on lane l nearest p within reach, or 0xFFFF
uint ptRingStepAt(PtLayout L, uint l, float2 p, float reach)
{
    uint best = 0xFFFFu;
    float bd = reach, r = ptRingRad(L, l);
    [loop] for (uint i = 0u; i < ptLen(l); i++)
    {
        float d = length(ptRingPoint(L, r, ptStepAngle(l, i)) - p);
        if (d < bd) { bd = d; best = i; }
    }
    return best;
}

// ---------------------------------------------------------------- the inspectors and the tools
float4 ptField(PtLayout L, uint f, float s)
{
    // lane fields along the lane inspector, step fields along the step inspector, tempo in the tools
    if (f <= PT_F_HITS)
    {
        float w = min((L.laneI.z - L.laneI.x - 20.0 * s) / 4.0, 150.0 * s);
        float x = L.laneI.x + 10.0 * s + f * w;
        return float4(x + 4.0 * s, L.laneI.y + 44.0 * s, x + w - 8.0 * s, L.laneI.y + 66.0 * s);
    }
    if (f <= PT_F_NUDGE)
    {
        float w = (L.stepI.z - L.stepI.x - 20.0 * s) / 3.0;
        float x = L.stepI.x + 10.0 * s + (f - PT_F_VEL) * w;
        return float4(x + 4.0 * s, L.stepI.y + 44.0 * s, x + w - 8.0 * s, L.stepI.y + 66.0 * s);
    }
    float x = L.tools.z - (f == PT_F_BPM ? 330.0 : 170.0) * s;
    return float4(x, L.tools.y + 3.0 * s, x + 150.0 * s, L.tools.w - 3.0 * s);
}
float4 ptLaneChip(PtLayout L, uint i, float s)      // 0 MUTE, 1 SOLO
{
    float x = L.laneI.x + 10.0 * s + i * 74.0 * s;
    return float4(x + 4.0 * s, L.laneI.y + 84.0 * s, x + 68.0 * s, L.laneI.y + 110.0 * s);
}
float4 ptRatchets(PtLayout L, float s) { return float4(L.stepI.x + 14.0 * s, L.stepI.y + 88.0 * s, min(L.stepI.x + 214.0 * s, L.stepI.z - 10.0 * s), L.stepI.y + 110.0 * s); }
float4 ptLayers(PtLayout L, float s) { return float4(L.tools.x, L.tools.y + 3.0 * s, L.tools.x + 430.0 * s, L.tools.w - 3.0 * s); }
float4 ptPlayChip(PtLayout L, float s) { float x = L.tools.x + 446.0 * s; return float4(x, L.tools.y + 2.0 * s, x + 72.0 * s, L.tools.w - 2.0 * s); }

// ---------------------------------------------------------------- the tape
#define PT_TAPE_BEHIND 28.0          // steps of history shown left of now
#define PT_TAPE_AHEAD  4.0           // steps shown right of now (what has been sent ahead)
float ptTapeX(PtLayout L, float rel, float x0, float x1) { return lerp(x0, x1, (rel + PT_TAPE_BEHIND) / (PT_TAPE_BEHIND + PT_TAPE_AHEAD)); }

#endif
