// Scope - shared constants, the record layout and the geometry both passes use (the sample pass
// hit-tests the same rects the layout pass draws).
//
// Records (32 bytes, the lab's a/b/c/d/e/f shape):
//   0      header  a = (now: the display's right edge, window s), b = (cursor A, cursor B time;
//                  0 = none), c = key latches (bit0 Space, bit1 Z, bit2 X), d = flags (bit0 hold,
//                  bit1 dragging A, bit2 dragging B, bit3 B is the active cursor), e = event
//                  watermark, f = samples written
//   1..    ring    a = (time, gate), b = (probe A, probe B), c = probe C, d = probe D
// Times are this node's _Time. Cursors are attached to data time, so a cursor rides its moment
// as the trace scrolls, and is dropped when that moment leaves the window.
#ifndef SCOPE_HLSLI
#define SCOPE_HLSLI

#define SC_HEAD   0u
#define SC_RING0  1u
#define SC_N      1024u           // ~17 s at 60 fps
#define SC_COUNT  (SC_RING0 + SC_N)
#define SC_LANES  4u
#define SC_COLS   128u            // trace columns (two per layout thread)
#define SC_SLOTS  13u             // per column: 3 per lane + the gate
#define SC_WIN_MIN 1.0
#define SC_WIN_MAX 16.0

#define SC_HOLD   1u
#define SC_DRAG_A 2u
#define SC_DRAG_B 4u
#define SC_ACTIVE_B 8u

struct ScRec { float2 a; float2 b; float c; float d; uint e; uint f; };

float4 scProbes(ScRec r) { return float4(r.b, r.c, r.d); }

struct ScLayout
{
    float4 head;
    float4 plot;          // lanes + gate strip, the trace area (x0..x1 is time)
    float4 lane[SC_LANES];
    float4 gate;
    float4 axis;
    float4 gutter;        // left of the plot: names and values
    float4 block;         // the plate behind gutter, plot and axis
};

ScLayout scLayout(float2 res, float s)
{
    ScLayout L;
    float m = 16.0 * s;
    L.head = float4(m, 14.0 * s, res.x - m, 44.0 * s);
    float top = 58.0 * s, bottom = res.y - 92.0 * s;
    L.block = float4(m, top - 10.0 * s, res.x - m, bottom + 30.0 * s);
    L.plot = float4(m + 188.0 * s, top, res.x - m - 14.0 * s, bottom);
    L.gutter = float4(m + 12.0 * s, top, L.plot.x - 16.0 * s, bottom);
    L.gate = float4(L.plot.x, bottom - 22.0 * s, L.plot.z, bottom);
    float laneBottom = L.gate.y - 10.0 * s;
    float gap = 8.0 * s;
    float h = (laneBottom - top - gap * (SC_LANES - 1u)) / SC_LANES;
    [unroll] for (uint i = 0u; i < SC_LANES; i++)
    {
        float y0 = top + i * (h + gap);
        L.lane[i] = float4(L.plot.x, y0, L.plot.z, y0 + h);
    }
    L.axis = float4(L.plot.x, bottom + 4.0 * s, L.plot.z, bottom + 24.0 * s);
    return L;
}

// time <-> x across the trace area
float scX(ScLayout L, float t, float now, float window) { return lerp(L.plot.z, L.plot.x, saturate((now - t) / window)); }
float scT(ScLayout L, float x, float now, float window) { return now - window * saturate((L.plot.z - x) / max(L.plot.z - L.plot.x, 1.0)); }

#endif
