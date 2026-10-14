// LT_Bench / rail.hlsli — the spectral rail's readings, shared by the drawing (canvas.hlsl) and the
// type (layout.hlsl), so the SPREAD in the header, the numbers on the deviation axis and the curve
// itself are one computation and can never disagree.
//
// Include AFTER declaring `StructuredBuffer<PathSeg> Chief` (SM 5.0 cannot pass a resource as a
// function argument, so this reaches the buffer by name), and after il_core.hlsli (palette).
#ifndef LT_RAIL_HLSLI
#define LT_RAIL_HLSLI

#define CHIEF_LANES 32
#define CHIEF_STRIDE (CHIEF_LANES * LT_MAX_SEG)

// Event -> a value on the grey ladder, plus whether it is an alarm or the accent event.
// EXIT is the accent because refraction OUT of the glass is the dispersing event: it is the
// thing the whole instrument is watching for.
float3 eventColour(int ev, float power)
{
    float t = (ev == EV_EMIT) ? 0.30 : (ev == EV_ENTER) ? 0.55 : (ev == EV_MIRROR) ? 0.70
            : (ev == EV_FRESNEL) ? 0.40 : (ev == EV_SCREEN) ? 0.85 : (ev == EV_ABSORB) ? 0.15
            : 0.22;
    float3 c = ptRamp(t * saturate(0.35 + power));
    if (ev == EV_EXIT) c = PT_ACCENT;
    if (ev == EV_TIR || ev == EV_EXHAUST) c = PT_ALARM;
    return c;
}

// THE RAIL'S BLOCK ONLY. The chief buffer carries one block per emitter, but a spread, an event
// ladder and a deviation profile are readings of ONE beam: averaging them across sources would
// print a number no beam on the bench actually produces.
//
// The spread is the angle between the extreme wavelengths WHERE THEY END UP, so it is taken from
// each lane's LAST live segment. Scanning every segment instead would fold in the partial bend at
// the entry face and report a number nothing in the picture corresponds to.
struct RailStats
{
    float devMin;     // radians, final deviation of the least-bent lane
    float devMax;     // radians, final deviation of the most-bent lane
    int   maxDepth;   // interactions in the deepest lane = the ladder's column count
    bool  anyLive;    // the rail's source has a live beam at all
    uint  events;     // one bit per EV_ code that ends a live segment (the ladder's legend)
};

RailStats ltRailStats(uint railBase)
{
    RailStats r;
    r.devMin = 1e9; r.devMax = -1e9; r.maxDepth = 1; r.anyLive = false; r.events = 0u;
    [loop] for (uint li = 0u; li < (uint)CHIEF_LANES; ++li)
    {
        float lastDev = 0.0; bool laneLive = false;
        [loop] for (uint sgi = 0u; sgi < (uint)LT_MAX_SEG; ++sgi)
        {
            PathSeg g = Chief[railBase + li * (uint)LT_MAX_SEG + sgi];
            if (!ltSegLive(g)) break;
            r.maxDepth = max(r.maxDepth, (int)g.depth + 1);
            r.events |= 1u << (uint)clamp(g.evtEnd, 0.0, (float)(EV_COUNT - 1));
            lastDev = g.dev; laneLive = true;
        }
        if (!laneLive) continue;
        r.anyLive = true;
        r.devMin = min(r.devMin, lastDev);
        r.devMax = max(r.devMax, lastDev);
    }
    if (!r.anyLive) { r.devMin = 0.0; r.devMax = 0.0; }
    return r;
}

// The deviation axis in degrees, padded so the curve never sits on the frame.
void ltDevRange(RailStats r, out float lo, out float hi)
{
    lo = degrees(r.devMin); hi = degrees(r.devMax);
    float pad = max((hi - lo) * 0.18, 1.5);
    lo -= pad; hi += pad;
}
float ltDevToX(float4 plot, float devDeg, float lo, float hi)
{
    return lerp(plot.x, plot.z, saturate((devDeg - lo) / max(hi - lo, 1e-3)));
}

// The ladder's cell grid: column = interaction index, row = lane, RED AT THE TOP (row 0 at the
// bottom), matching the wavelength axis beside it.
float2 ltLadderCell(float4 ladder, int maxDepth) { return float2((ladder.z - ladder.x) / (float)max(maxDepth, 1), (ladder.w - ladder.y) / (float)CHIEF_LANES); }

// THE RAIL'S VERTICAL AXIS IS ITS LANES. Row r of the ladder and of the deviation profile is lane r
// of the rail source, so the two plots line up row for row. Wavelength runs linearly up the rows
// only for a continuous spectrum: a laser triad puts its three lines on three blocks of rows and a
// narrow band spreads a few nanometres over all of them. So the axis names the wavelengths the
// source actually emits, at the rows that carry them, never a 400-700 scale it does not have.
float ltRailRowY(float4 box, float row) { return box.w - (row + 0.5) * (box.w - box.y) / (float)CHIEF_LANES; }

// Up to four labelled rows: each wavelength and the (fractional) row it sits on. Needs optics.hlsli.
uint ltRailAxis(int spec, float band0, float band1, out float4 wl, out float4 row)
{
    float n1 = (float)(CHIEF_LANES - 1);
    wl = float4(400.0, 500.0, 600.0, 700.0);
    row = (wl - WL_MIN) / (WL_MAX - WL_MIN) * n1;
    if (spec == SP_BAND)
    {
        wl = float4(ltLaneWavelength(0u, (uint)CHIEF_LANES, spec, band0, band1),
                    ltLaneWavelength((uint)CHIEF_LANES / 2u, (uint)CHIEF_LANES, spec, band0, band1),
                    ltLaneWavelength((uint)CHIEF_LANES - 1u, (uint)CHIEF_LANES, spec, band0, band1), 0.0);
        row = float4(0.0, (float)(CHIEF_LANES / 2), n1, 0.0);
        return 3u;
    }
    if (spec == SP_TRIAD)
    {
        // one label per run of equal wavelength, at the middle of its block, read off the lane map
        uint n = 0u, first = 0u;
        float prev = ltLaneWavelength(0u, (uint)CHIEF_LANES, spec, band0, band1);
        [loop] for (uint i = 1u; i <= (uint)CHIEF_LANES; ++i)
        {
            float w = (i < (uint)CHIEF_LANES) ? ltLaneWavelength(i, (uint)CHIEF_LANES, spec, band0, band1) : -1.0;
            if (w != prev && n < 4u)
            {
                float4 at = float4((float)(n == 0u), (float)(n == 1u), (float)(n == 2u), (float)(n == 3u));
                wl = lerp(wl, prev.xxxx, at);
                row = lerp(row, (0.5 * (float)(first + i - 1u)).xxxx, at);
                n++; first = i; prev = w;
            }
        }
        return n;
    }
    return 4u;
}

#endif
