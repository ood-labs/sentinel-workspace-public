// Audio Bands / view - the panel's geometry and hover rules, shared by the drawing (render.hlsl)
// and its type and chrome (layout.hlsl), so what is drawn, what is labelled and what lights under
// the pointer cannot disagree.
//
// The spectrum's extents are NOT defined here. They stay bands.hlsli's (abPlotTop, abPlotBot,
// abHzToX across the full width, abThreshToY), because events.hlsl hit-tests exactly those; this
// file only places the plate around them. Everything under the split is a readout the event pass
// never tests, so the trace strips are laid out here from the live extent.
//
// Include after il_core.hlsli, bands.hlsli and the Bands / Det / Cols buffer declarations.
#ifndef AB_VIEW_HLSLI
#define AB_VIEW_HLSLI

// events.hlsl's THR_GRAB_UNITS: how near the threshold bar a left press grabs it, in UI units.
#define AB_GRAB_UNITS 4.5
// Smallest full scale a strip will use. Without a floor, a silent lane would autoscale its own
// noise up to full height and look like it was working.
#define AB_FLUX_MIN_FS 6.0

// The kit's UI scale (1.0 at 1280 x 720), floored so a caption never renders under 9 px on a
// small dock.
float abS(float2 R) { return max(ilCtx(R).s, 0.86); }

// Octave o of the ruler: 31.25 Hz doubling to 16 kHz (o = 0..9).
float abOctHz(int o) { return 31.25 * exp2((float)o); }

// ---------------------------------------------------------------- the spectrum plate
// Full width, because the log-Hz axis spans the whole panel and the drag maps pointer x across it;
// from just above the band rail to just above the split, with the octave ruler in its foot.
float4 abSpecPlate(float2 R)
{
    float u = abUI(R.y);
    return float4(0.0, abPlotTop(R.y) - 2.0 * u, R.x, floor(R.y * AB_SPEC_BOT) - u);
}

// ---------------------------------------------------------------- the trace strips
// The keycap footer, when the dock is tall enough to afford one.
float abFootH(float2 R)
{
    float s = abS(R);
    return (R.y - floor(R.y * AB_SPEC_BOT) >= 150.0 * s) ? ilSnap(26.0 * s) : 0.0;
}

// Lane strip 0 kick, 1 snare, 2 hat: full width under the split.
float4 abLaneRect(uint lane, float2 R)
{
    float s = abS(R);
    float g = max(ilSnap(3.0 * s), 2.0);
    float top = floor(R.y * AB_SPEC_BOT) + g;
    float foot = abFootH(R);
    float bot = R.y - (foot > 0.0 ? foot : g);
    float h = max((bot - top - 2.0 * g) / 3.0, 8.0);
    float y0 = floor(top + (float)lane * (h + g));
    return float4(0.0, y0, R.x, floor(y0 + h));
}

// Inside a strip: a caption row (name, full scale, hit count), the plot under it, and the
// detection lamp at the plot's right end - the live edge, where the newest hop is drawn.
float abCapH(float2 R) { return ilSnap(18.0 * abS(R)); }
float abLampW(float2 R) { return ilSnap(14.0 * abS(R)); }

float4 abLanePlot(uint lane, float2 R)
{
    float s = abS(R);
    float4 r = abLaneRect(lane, R);
    return float4(r.x + 10.0 * s, r.y + abCapH(R), r.z - 18.0 * s - abLampW(R), max(r.w - 5.0 * s, r.y + abCapH(R) + 4.0));
}

float4 abLamp(uint lane, float2 R)
{
    float s = abS(R);
    float4 r = abLaneRect(lane, R);
    float4 p = abLanePlot(lane, R);
    return float4(r.z - 10.0 * s - abLampW(R), p.y, r.z - 10.0 * s, p.w);
}

// Hops a strip shows (trace_seconds of history at the producer's hop rate), and its full scale.
// The THRESHOLD is part of the scale, not just the signal: without it a threshold above the
// recent peak pins its line to the top edge where it reads as the strip border.
float abTraceShow(float hopDt) { return clamp(trace_seconds / max(hopDt, 1e-6), 8.0, (float)AB_TRACE - 2.0); }
float abFullScale(uint lane) { return max(max(Det[abStateB(lane)].w, Bands[lane].w), AB_FLUX_MIN_FS) * 1.15; }

// ---------------------------------------------------------------- hover (never stored)
// The pointer in panel pixels, or (-1, -1) when it is outside the canvas.
float2 abPointer(float2 R)
{
    float2 n = _ViewportPointerPosition;
    return (all(n >= 0.0) && all(n <= 1.0)) ? n * R : float2(-1.0, -1.0);
}

// The band a press here would grab: events.hlsl's rule - in the spectrum half, inside a band's
// span, nearest centre wins - so hover lights exactly what a drag would move. -1 for none.
int abBandAt(float2 ptr, float2 R, float hzMax)
{
    if (hzMax <= 0.0 || ptr.x < 0.0 || ptr.y < 0.0 || ptr.y >= R.y * AB_SPEC_BOT) return -1;
    float x = ptr.x / R.x;
    int hit = -1;
    float best = 1e9;
    [loop] for (uint L = 0u; L < AB_LANES; ++L)
    {
        float4 b = Bands[L];
        if (b.z < 0.5 || b.y <= b.x) continue;
        float x0 = abHzToX(b.x, hzMax), x1 = abHzToX(b.y, hzMax);
        if (x < x0 || x > x1) continue;
        float d = abs(x - 0.5 * (x0 + x1));
        if (d < best) { best = d; hit = (int)L; }
    }
    return hit;
}

// Whether a left press here would take the band's threshold bar instead of moving the band.
bool abOnBar(float2 ptr, uint lane, float H)
{
    return abs(ptr.y - abThreshToY(Bands[lane].w, H)) < AB_GRAB_UNITS * abUI(H);
}

// The strip under the pointer, or -1.
int abLaneAt(float2 ptr, float2 R)
{
    if (ptr.y < R.y * AB_SPEC_BOT) return -1;
    [loop] for (uint l = 0u; l < AB_LANES; ++l) if (ilIn(ptr, abLaneRect(l, R))) return (int)l;
    return -1;
}

// The band events.hlsl is holding (move, resize or threshold), or -1. Mode 3 is the threshold.
int abHeldLane() { float4 d = Bands[AB_DRAG]; return (d.x > 0.5 && d.w < 3.5) ? (int)clamp(Bands[AB_GRAB].x, 0.0, 2.0) : -1; }
bool abHeldBar() { return Bands[AB_DRAG].w > 2.5; }

#endif
