// FM_Colony / colony_view.hlsli - where the canvas puts things, in ONE place.
//
// Included by the drawing (canvas.hlsl), the type and chrome (layout.hlsl) and the history pass
// (mtrace.hlsl), so a plate, its border, its caption and anything the pointer is tested against
// all come from the same rectangles. Every rect derives from the live extent: a margin, a title
// row and a keycap footer cut off the edges, the readout column off the right, the gait chart off
// the bottom of what is left, and the arena gets the rest.
#ifndef FM_COLONY_VIEW_HLSLI
#define FM_COLONY_VIEW_HLSLI

// The colony-wide history the readout column traces: one sample every FC_TRACE_DT seconds of wall
// clock, FC_TRACE_N of them (about four seconds, eight beats at 120 bpm). Element 0 of the buffer
// is the header (cursor, samples written, time owed, magic); samples are (speed, slip, traffic,
// laden).
#define FC_TRACE_N     128u
#define FC_TRACE_DT    0.0333333
#define FC_TRACE_MAGIC 4417.0

// The kit's UI scale (1.0 at 1280 x 720), floored so a caption never renders under 9 px.
float fcS(float2 R) { return max(ilCtx(R).s, 0.86); }

struct FcView
{
    float  s;
    float4 head;     // title row
    float4 arena;    // the live arena plate
    float4 draw;     // inside it, the rectangle the arena is fitted into
    float4 gait;     // the footfall chart plate
    float4 chart;    // inside it, the chart: six stance lanes and a speed lane
    float4 col;      // the readout column
    float4 foot;     // keycap footer
};

FcView fcView(float2 R)
{
    FcView v;
    float s = fcS(R);
    v.s = s;
    float m = ilSnap(12.0 * s);
    float4 r = float4(m, 0.0, R.x - m, R.y);
    v.head = ilCutTop(r, ilSnap(34.0 * s));
    v.foot = ilCutBottom(r, ilSnap(30.0 * s));
    v.col = ilCutRight(r, clamp(0.25 * R.x, 230.0 * s, 300.0 * s));
    r.z -= ilSnap(10.0 * s);
    v.gait = ilCutBottom(r, clamp(0.19 * R.y, 128.0 * s, 210.0 * s));
    r.w -= ilSnap(10.0 * s);
    v.arena = r;
    // caption row above the arena, legend row below it
    v.draw = float4(r.x + 10.0 * s, r.y + 26.0 * s, r.z - 10.0 * s, r.w - 26.0 * s);
    // lane captions on the left, a caption row above
    v.chart = float4(v.gait.x + 52.0 * s, v.gait.y + 26.0 * s, v.gait.z - 12.0 * s, v.gait.w - 8.0 * s);
    return v;
}

// The shared top-down projection of the arena into its plate (formic.hlsli), so the ants the
// drawing puts down are exactly the ones the pointer finds.
FmTop fcArenaTop(FcView v, FmRec arena) { return fmTopFit(v.draw.xy, v.draw.zw, arena, 0.96); }

// Gait chart: seven lanes, the six legs ordered BY TRIPOD (left front, left rear, right middle,
// then left middle, right front, right rear) and the speed trace along the bottom.
float fcLaneH(FcView v) { return (v.chart.w - v.chart.y) / 7.0; }
uint  fcLaneLeg(uint row) { return (row == 0u) ? 0u : (row == 1u) ? 2u : (row == 2u) ? 4u : (row == 3u) ? 1u : (row == 4u) ? 3u : 5u; }

// Which history sample a chart x shows: oldest at the left, newest at the right, walked back from
// the ring's cursor so the trace scrolls rather than jumping when the write wraps.
uint fcGaitSample(FcView v, float x, uint cursor, uint written)
{
    float u = saturate((x - v.chart.x) / max(v.chart.z - v.chart.x, 1.0));
    uint span = max(min(written, FM_GAIT_HIST), 1u);
    uint back = min((uint)((1.0 - u) * (float)(span - 1u) + 0.5), span - 1u);
    return (cursor + FM_GAIT_HIST - 1u - back) % FM_GAIT_HIST;
}

// The pointer in canvas pixels, or (-1, -1) when it is outside the canvas (hover is never stored).
float2 fcPointer(float2 R)
{
    float2 n = _ViewportPointerPosition;
    return (all(n >= 0.0) && all(n <= 1.0)) ? n * R : float2(-1.0, -1.0);
}

// How near an ant's body the pointer must be to inspect it, in pixels.
#define FC_PICK_PX 14.0

#endif
