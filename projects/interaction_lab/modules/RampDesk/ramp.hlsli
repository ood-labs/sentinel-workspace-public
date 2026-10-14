// Ramp Desk - the record layout, the stop maths and the geometry every pass shares (the reducer
// hit-tests exactly what the layout pass draws).
//
// ONE buffer, float4 records. Its head IS the published "Palette" (../_shared/palette.hlsli):
//   0..24     head + 12 stops                 saved (state_buffers), published
//   25..280   the 256 entries                 recomputed by the reducer, published
//   --- the desk's own working state: never saved, never restored ---
//   281  V0   (event watermark low 16 bits, high 16 bits, the built-in palette R loaded last, -)
//   282  V1   (drag mode, drag target, selected stop, flags: bit 0 a dragged stop will be removed)
//   283  V2   (press x px, press y px, grab offset px, working-state magic)
//   284..308  the undo snapshot of 0..24 (also every drag's origin)
//   309  U0   (1 when a snapshot exists, -, -, -)
//
// Why one buffer: the reducer is the only pass with `time_dependent: false`, so it runs only when
// there is input (or a parameter, the panel size or a reload changes). Publishing the palette from
// the buffer it owns means the Palette's generation moves only then, and an `on_dirty` consumer
// sleeps the rest of the time. A separate palette pass would have to run after the reducer in the
// same cook, and on 0.6.3 passes run in reverse manifest order (see PLAN.md).
#ifndef RAMP_HLSLI
#define RAMP_HLSLI

#ifdef RD_STATE_RW
RWStructuredBuffer<float4> S : register(u0);
#else
StructuredBuffer<float4> S : register(t0);
#endif
#define PAL_BUFFER S
#include "../_shared/palette.hlsli"

#define RD_V0     281u
#define RD_V1     282u
#define RD_V2     283u
#define RD_UNDO0  284u
#define RD_U0     309u
#define RD_COUNT  310u
#define RD_VMAGIC 12409.0          // working state written by this format (an exact float)

#define RD_REMOVE 1u

#define RD_PLANE_CMAX 0.33         // the picker plane's chroma axis, 0 .. this

uint   rdN()              { return clamp((uint)S[PAL_HEAD].x, 2u, PAL_STOPS); }
float  rdT(uint i)        { return S[PAL_STOP0 + 2u * i].x; }
float  rdMid(uint i)      { return S[PAL_STOP0 + 2u * i].y; }
float3 rdAsked(uint i)    { return S[PAL_STOP0 + 2u * i + 1u].xyz; }        // (L, C asked, h)
float3 rdShown(uint i)    { float4 b = S[PAL_STOP0 + 2u * i + 1u]; return float3(b.x, b.w, b.z); }
bool   rdClipped(uint i)  { float4 b = S[PAL_STOP0 + 2u * i + 1u]; return b.y > b.w + 0.002; }
uint   rdSel()            { return min((uint)S[RD_V1].z, rdN() - 1u); }

// The stop interval holding t: i with t_i <= t < t_i+1 (the ends hold the end stops' colours).
// Returns the biased blend position in u; i = n - 1 means past the last stop.
uint rdSegment(float t, out float u)
{
    uint n = rdN();
    u = 0.0;
    if (t <= rdT(0u)) return 0u;
    [loop] for (uint i = 0u; i + 1u < n; i++)
    {
        float a = rdT(i), b = rdT(i + 1u);
        if (t < b)
        {
            u = b > a + 1e-6 ? palBias((t - a) / (b - a), rdMid(i)) : 1.0;
            return i;
        }
    }
    u = 1.0;
    return n - 2u;
}

// The palette at t blended in a space (linear RGB inside sRGB), straight from the stops.
float3 rdBlendAt(float t, uint space, out bool clipped)
{
    float u;
    uint i = rdSegment(t, u);
    return palBlend(rdShown(i), rdShown(i + 1u), u, space, clipped);
}

// ---------------------------------------------------------------- geometry
struct RdLayout
{
    float4 head;
    float4 hint;
    float4 block;
    float4 left;
    float4 row0;               // the first stop row; row i is row0 moved down i * rowStep
    float  rowStep;
    float4 pick;               // the picker pane (title row at its top)
    float4 plane;              // lightness (up) x chroma (right) at the selected stop's hue
    float4 hue;                // the hue strip, 0 .. 360
    float4 readout;
    float4 right;
    float4 bar;                // the ramp
    float4 pins;               // the stops' lane under it
    float4 lane[10];           // 0 OKLab 1 OKLCH 2 sRGB | 3 lightness 4 deutan 5 protan 6 tritan | 7 L 8 C 9 step
    float4 groupT[3];          // each lane group's caption row
};

RdLayout rdLayout(float2 res, float s)
{
    RdLayout L;
    float m = 16.0 * s;
    L.head = float4(m, 14.0 * s, res.x - m, 44.0 * s);
    L.hint = float4(m, res.y - 41.0 * s, res.x - m, res.y - 11.0 * s);
    L.block = float4(m, 54.0 * s, res.x - m, L.hint.y - 10.0 * s);
    float4 inner = ilInset(L.block, 12.0 * s);

    // left: the stops, then the picker
    L.left = float4(inner.x, inner.y, inner.x + 288.0 * s, inner.w);
    L.rowStep = 24.0 * s;
    L.row0 = float4(L.left.x, L.left.y + 30.0 * s, L.left.z, L.left.y + 52.0 * s);
    float py = L.left.y + 30.0 * s + PAL_STOPS * L.rowStep + 12.0 * s;
    L.pick = float4(L.left.x, py, L.left.z, L.left.w);
    float planeTop = py + 30.0 * s;
    float planeH = clamp(L.left.w - planeTop - 66.0 * s, 96.0 * s, 1.25 * 288.0 * s);
    L.plane = float4(L.left.x, planeTop, L.left.z, planeTop + planeH);
    L.hue = float4(L.left.x, L.plane.w + 8.0 * s, L.left.z, L.plane.w + 22.0 * s);
    L.readout = float4(L.left.x, L.hue.w + 6.0 * s, L.left.z, L.left.w);

    // right: the ramp, then three groups of lanes on the ramp's own t axis
    L.right = float4(L.left.z + 16.0 * s, inner.y, inner.z, inner.w);
    float x0 = L.right.x + 76.0 * s, x1 = L.right.z;
    float h = L.right.w - L.right.y;
    float rampH = clamp(0.17 * h, 56.0 * s, 132.0 * s);
    L.bar = float4(x0, L.right.y + 30.0 * s, x1, L.right.y + 30.0 * s + rampH);
    L.pins = float4(x0, L.bar.w, x1, L.bar.w + 34.0 * s);
    float stripH = clamp(0.03 * h, 14.0 * s, 22.0 * s), gap = 4.0 * s;
    float y = L.pins.w + 8.0 * s;
    L.groupT[0] = float4(L.right.x, y, x1, y + 18.0 * s);
    y = L.groupT[0].w;
    [unroll] for (uint a = 0u; a < 3u; a++) { L.lane[a] = float4(x0, y, x1, y + stripH); y += stripH + gap; }
    y += 6.0 * s;
    L.groupT[1] = float4(L.right.x, y, x1, y + 18.0 * s);
    y = L.groupT[1].w;
    [unroll] for (uint b = 3u; b < 7u; b++) { L.lane[b] = float4(x0, y, x1, y + stripH); y += stripH + gap; }
    y += 6.0 * s;
    L.groupT[2] = float4(L.right.x, y, x1, y + 18.0 * s);
    y = L.groupT[2].w;
    float rest = max(L.right.w - y - 2.0 * 8.0 * s, 90.0 * s);
    float gL = rest * 0.4, gC = rest * 0.3, gD = rest * 0.3;
    L.lane[7] = float4(x0, y, x1, y + gL); y += gL + 8.0 * s;
    L.lane[8] = float4(x0, y, x1, y + gC); y += gC + 8.0 * s;
    L.lane[9] = float4(x0, y, x1, y + gD);
    return L;
}

float4 rdRow(RdLayout L, uint i) { return L.row0 + float4(0.0, 1.0, 0.0, 1.0) * (L.rowStep * i); }
float  rdX(RdLayout L, float t)  { return lerp(L.bar.x, L.bar.z, saturate(t)); }
float  rdTOf(RdLayout L, float x) { return saturate((x - L.bar.x) / max(L.bar.z - L.bar.x, 1.0)); }

// a stop's pin: a tick up into the ramp and a swatch hanging under it
float4 rdPinSwatch(RdLayout L, float x, float s) { return float4(x - 7.0 * s, L.pins.y + 7.0 * s, x + 7.0 * s, L.pins.y + 21.0 * s); }
float  rdMidY(RdLayout L, float s) { return L.pins.y + 28.0 * s; }
// the midpoint diamond between stops i and i + 1
float  rdMidX(RdLayout L, uint i) { float a = rdT(i), b = rdT(i + 1u); return rdX(L, a + rdMid(i) * (b - a)); }
bool   rdMidShown(RdLayout L, uint i, float s) { return rdX(L, rdT(i + 1u)) - rdX(L, rdT(i)) > 26.0 * s; }

// the picker plane <-> (L, C)
float2 rdPlaneLC(RdLayout L, float2 p)
{
    float2 v = saturate((p - L.plane.xy) / max(L.plane.zw - L.plane.xy, 1.0));
    return float2(1.0 - v.y, v.x * RD_PLANE_CMAX);
}
float2 rdPlanePx(RdLayout L, float lightness, float chroma)
{
    return float2(lerp(L.plane.x, L.plane.z, saturate(chroma / RD_PLANE_CMAX)), lerp(L.plane.w, L.plane.y, saturate(lightness)));
}

// ---------------------------------------------------------------- hit tests
// the stop whose pin (or tick into the ramp) is nearest within reach px, or 0xFFFF
uint rdHitPin(RdLayout L, float2 at, float s)
{
    if (at.y < L.bar.w - 10.0 * s || at.y > L.pins.y + 24.0 * s) return 0xFFFFu;
    uint n = rdN(), best = 0xFFFFu;
    float bd = 9.0 * s;
    [loop] for (uint i = 0u; i < n; i++)
    {
        float d = abs(rdX(L, rdT(i)) - at.x);
        if (d < bd) { bd = d; best = i; }
    }
    return best;
}

uint rdHitMid(RdLayout L, float2 at, float s)
{
    if (abs(at.y - rdMidY(L, s)) > 8.0 * s) return 0xFFFFu;
    uint n = rdN(), best = 0xFFFFu;
    float bd = 8.0 * s;
    [loop] for (uint i = 0u; i + 1u < n; i++)
    {
        if (!rdMidShown(L, i, s)) continue;
        float d = abs(rdMidX(L, i) - at.x);
        if (d < bd) { bd = d; best = i; }
    }
    return best;
}

bool rdOnRamp(RdLayout L, float2 at) { return ilIn(at, float4(L.bar.x, L.bar.y, L.bar.z, L.pins.w)); }

#endif
