// Patch Bay - the record layout, the sources and the geometry every pass shares (the reducer
// hit-tests exactly what the layout pass draws).
//
// "state" buffer, float4 records; integers are stored as exact float values.
//   0        head      (cables n, format magic, muted 0 | 1, -)               saved
//   1..6     output d  (base 0..1, -, -, -)                                   saved
//   7..22    cable k   (source 0..5, output 0..5, depth -1..1, -)             saved
//   --- working state: never saved, never restored ---
//   23  V0   (event watermark low 16 bits, high 16 bits, history head, working magic)
//   24  V1   (drag mode, drag target, selected cable or -1, the dragged value when the drag began)
//   25  V2   (press x px, press y px, pointer x px, pointer y px)
//   26  PH   phases of sources 1-4 (turns)
//   27  PH2  (phase of source 5, history clock s, -, -)
//   28  SRC  source values 1-4 now          29  SRC2 (source 5, source 6, -, -)
//   30  OUT  outputs 1-4 now                 31  OUT2 (output 5, output 6, -, -)   <- control outputs
//   32..54   the undo snapshot of 0..22
//   55  U0   (1 when a snapshot exists)
//   56..223  history rings: lane 0 the external input, lanes 1-6 the outputs; 96 samples a lane,
//            four to a record (24 records a lane), one sample every 1/50 s
//
// A source is unipolar (0..1); patched, it swings its output around the output's base:
//   out = base + sum over cables (depth * (2 * source - 1) * 0.5), clamped 0..1
// so depth 1 sweeps the whole base +- 0.5 and a negative depth inverts the source.
#ifndef BAY_HLSLI
#define BAY_HLSLI

#ifdef PB_STATE_RW
RWStructuredBuffer<float4> S : register(u0);
#else
StructuredBuffer<float4> S : register(t0);
#endif

#define PB_SRC     6u
#define PB_OUT     6u
#define PB_CABLES  16u
#define PB_HEAD    0u
#define PB_BASE0   1u
#define PB_CABLE0  7u
#define PB_SAVED   23u
#define PB_V0      23u
#define PB_V1      24u
#define PB_V2      25u
#define PB_PH      26u
#define PB_PH2     27u
#define PB_SRCV    28u
#define PB_SRCV2   29u
#define PB_OUTV    30u
#define PB_OUTV2   31u
#define PB_UNDO0   32u
#define PB_U0      55u
#define PB_HIST0   56u
#define PB_HIST_N  96u
#define PB_HIST_RECS 24u
#define PB_COUNT   224u
#define PB_MAGIC   410.0
#define PB_VMAGIC  12410.0
#define PB_HIST_DT 0.02
#define PB_MUTED   1.0

// drag modes (V1.x)
#define DM_NONE     0u
#define DM_FROM_SRC 1u          // a new cable from a source jack
#define DM_FROM_DST 2u          // a new cable from an empty output jack
#define DM_REPLUG   3u          // a plug pulled out of an output jack
#define DM_DEPTH    4u          // the selected cable's knob
#define DM_CELL     5u          // a matrix cell, up and down
#define DM_BASE     6u          // along an output's meter

uint   pbCables()          { return min((uint)S[PB_HEAD].x, PB_CABLES); }
bool   pbMuted()           { return S[PB_HEAD].z > 0.5; }
float4 pbCable(uint k)     { return S[PB_CABLE0 + k]; }
uint   pbCSrc(uint k)      { return (uint)S[PB_CABLE0 + k].x; }
uint   pbCDst(uint k)      { return (uint)S[PB_CABLE0 + k].y; }
float  pbDepth(uint k)     { return S[PB_CABLE0 + k].z; }
float  pbBase(uint d)      { return S[PB_BASE0 + d].x; }
// four to a record, the fifth and sixth in the next one (an index never runs past a float4, so a
// literal index cannot trip FXC's bounds check the way `i < 4 ? a[i] : b[i - 4]` does)
float  pbSrcNow(uint i)    { return S[PB_SRCV + i / 4u][i % 4u]; }
float  pbOutNow(uint d)    { return S[PB_OUTV + d / 4u][d % 4u]; }
float  pbPhase(uint i)     { return S[PB_PH + i / 4u][i % 4u]; }
int    pbSel()             { return (int)S[PB_V1].z; }

// lane 0 is the external input, lanes 1-6 the outputs; age 0 is the newest sample
float pbHist(uint lane, uint age)
{
    uint head = (uint)S[PB_V0].z;
    uint i = (head + PB_HIST_N - 1u - min(age, PB_HIST_N - 1u)) % PB_HIST_N;
    return S[PB_HIST0 + lane * PB_HIST_RECS + i / 4u][i % 4u];
}

// ---------------------------------------------------------------- the sources
float pbHash(float x) { x = frac(x * 0.1031); x *= x + 33.33; x *= x + x; return frac(x); }

// a source at a phase (turns): sine, triangle, ramp, sample and hold, smooth drift; source 6 is
// the external input and has no phase
float pbWave(uint i, float ph)
{
    if (i == 0u) return 0.5 + 0.5 * sin(ph * 6.2831853);
    if (i == 1u) return 1.0 - abs(frac(ph) * 2.0 - 1.0);
    if (i == 2u) return frac(ph);
    if (i == 3u) return pbHash(floor(ph) * 7.13 + 0.37);
    float f = floor(ph), u = frac(ph);
    u = u * u * (3.0 - 2.0 * u);
    return lerp(pbHash(f * 3.71 + 1.9), pbHash((f + 1.0) * 3.71 + 1.9), u);
}

// sum over the cables into output d, and the reach of their swing
float pbModulate(uint d, float base, out float reach)
{
    float acc = 0.0;
    reach = 0.0;
    uint n = pbCables();
    [loop] for (uint k = 0u; k < n; k++)
    {
        float4 c = pbCable(k);
        if ((uint)c.y != d) continue;
        acc += c.z * (2.0 * pbSrcNow((uint)c.x) - 1.0) * 0.5;
        reach += abs(c.z) * 0.5;
    }
    return saturate(base + acc);
}

// ---------------------------------------------------------------- geometry
struct PbLayout
{
    float4 head;
    float4 hint;
    float4 block;
    float4 srcCol;             // the sources, left
    float4 dstCol;             // the outputs, right
    float4 rows;               // the band the rows share
    float  rowStep;
    float4 grid;               // the 6 x 6 cells (under the sources)
    float  cellW;
    float  cellH;
    float4 inspect;            // the selected cable (under the outputs)
};

PbLayout pbLayout(float2 res, float s)
{
    PbLayout L;
    float m = 16.0 * s;
    L.head = float4(m, 14.0 * s, res.x - m, 44.0 * s);
    L.hint = float4(m, res.y - 41.0 * s, res.x - m, res.y - 11.0 * s);
    L.block = float4(m, 54.0 * s, res.x - m, L.hint.y - 10.0 * s);
    float4 inner = ilInset(L.block, 12.0 * s);
    L.cellH = 30.0 * s;
    L.cellW = 56.0 * s;
    float bottomH = 30.0 * s + 22.0 * s + PB_SRC * L.cellH;
    float top = inner.y + 30.0 * s;
    float bot = inner.w - bottomH - 18.0 * s;
    L.rowStep = clamp((bot - top) / (float)PB_SRC, 44.0 * s, 120.0 * s);
    L.rows = float4(inner.x, top, inner.z, top + L.rowStep * PB_SRC);
    L.srcCol = float4(inner.x, top, inner.x + 330.0 * s, L.rows.w);
    L.dstCol = float4(inner.z - 430.0 * s, top, inner.z, L.rows.w);
    float my = inner.w - bottomH;
    L.grid = float4(inner.x + 76.0 * s, my + 52.0 * s, inner.x + 76.0 * s + PB_OUT * L.cellW, my + 52.0 * s + PB_SRC * L.cellH);
    L.inspect = float4(L.grid.z + 40.0 * s, my, inner.z, inner.w);
    return L;
}

float4 pbSrcRow(PbLayout L, uint i) { return float4(L.srcCol.x, L.rows.y + L.rowStep * i, L.srcCol.z, L.rows.y + L.rowStep * (i + 0.88)); }
float4 pbDstRow(PbLayout L, uint d) { return float4(L.dstCol.x, L.rows.y + L.rowStep * d, L.dstCol.z, L.rows.y + L.rowStep * (d + 0.88)); }
float2 pbSrcJack(PbLayout L, uint i, float s) { float4 r = pbSrcRow(L, i); return float2(r.z - 16.0 * s, ilMid(r).y); }
float2 pbDstJack(PbLayout L, uint d, float s) { float4 r = pbDstRow(L, d); return float2(r.x + 16.0 * s, ilMid(r).y); }
// a source row: name and kind, the scope of its last 1.92 s, its value and rate, the jack at its right
float4 pbScope(PbLayout L, uint i, float s) { float4 r = pbSrcRow(L, i); return float4(r.x + 104.0 * s, r.y + 6.0 * s, r.z - 96.0 * s, r.w - 6.0 * s); }
// an output row: the jack at its left, name and value over the meter (base, swing, live), its trace
float4 pbMeter(PbLayout L, uint d, float s) { float4 r = pbDstRow(L, d); float y = ilMid(r).y; return float4(r.x + 34.0 * s, y + 3.0 * s, r.x + 236.0 * s, y + 13.0 * s); }
float4 pbTrace(PbLayout L, uint d, float s) { float4 r = pbDstRow(L, d); return float4(r.x + 256.0 * s, r.y + 6.0 * s, r.z - 10.0 * s, r.w - 6.0 * s); }
// the inspector's depth knob
float2 pbKnob(PbLayout L, float s) { return float2(L.inspect.x + 58.0 * s, L.inspect.y + 104.0 * s); }
#define PB_KNOB_R 34.0
float4 pbCell(PbLayout L, uint i, uint d) { return float4(L.grid.x + d * L.cellW, L.grid.y + i * L.cellH, L.grid.x + (d + 1u) * L.cellW, L.grid.y + (i + 1u) * L.cellH); }

// a cable hangs from its source jack to its output jack: a quadratic with the middle pulled down
float2 pbCableAt(float2 a, float2 b, float t, float s)
{
    float2 c = 0.5 * (a + b) + float2(0.0, 0.16 * length(b - a) + 26.0 * s);
    float u = 1.0 - t;
    return u * u * a + 2.0 * u * t * c + t * t * b;
}
float2 pbCableMid(PbLayout L, uint k, float s) { return pbCableAt(pbSrcJack(L, pbCSrc(k), s), pbDstJack(L, pbCDst(k), s), 0.5, s); }

// ---------------------------------------------------------------- hit tests
uint pbHitSrcJack(PbLayout L, float2 at, float s)
{
    [loop] for (uint i = 0u; i < PB_SRC; i++) if (length(at - pbSrcJack(L, i, s)) < 14.0 * s) return i;
    return 0xFFFFu;
}
uint pbHitDstJack(PbLayout L, float2 at, float s)
{
    [loop] for (uint d = 0u; d < PB_OUT; d++) if (length(at - pbDstJack(L, d, s)) < 14.0 * s) return d;
    return 0xFFFFu;
}
// the newest cable within reach of the pointer along its length, or 0xFFFF
uint pbHitCable(PbLayout L, float2 at, float s)
{
    uint n = pbCables(), best = 0xFFFFu;
    float bd = 7.0 * s;
    [loop] for (uint k = 0u; k < n; k++)
    {
        float2 a = pbSrcJack(L, pbCSrc(k), s), b = pbDstJack(L, pbCDst(k), s);
        float2 prev = a;
        [loop] for (uint j = 1u; j <= 24u; j++)
        {
            float2 cur = pbCableAt(a, b, j / 24.0, s);
            float d = ilSdSeg(at, prev, cur);
            if (d <= bd) { bd = d; best = k; }
            prev = cur;
        }
    }
    return best;
}
// the newest cable plugged into output d, or 0xFFFF
uint pbCableAtDst(uint d)
{
    uint n = pbCables(), best = 0xFFFFu;
    [loop] for (uint k = 0u; k < n; k++) if (pbCDst(k) == d) best = k;
    return best;
}
// the matrix cell under a point (source * 6 + output), or 0xFFFF
uint pbHitCell(PbLayout L, float2 at)
{
    if (!ilIn(at, L.grid)) return 0xFFFFu;
    uint d = min((uint)((at.x - L.grid.x) / L.cellW), PB_OUT - 1u);
    uint i = min((uint)((at.y - L.grid.y) / L.cellH), PB_SRC - 1u);
    return i * PB_OUT + d;
}
uint pbHitMeter(PbLayout L, float2 at, float s)
{
    [loop] for (uint d = 0u; d < PB_OUT; d++) if (ilIn(at, ilInset(pbMeter(L, d, s), -5.0 * s))) return d;
    return 0xFFFFu;
}
uint pbFind(uint src, uint dst)
{
    uint n = pbCables();
    [loop] for (uint k = 0u; k < n; k++) if (pbCSrc(k) == src && pbCDst(k) == dst) return k;
    return 0xFFFFu;
}

#endif
