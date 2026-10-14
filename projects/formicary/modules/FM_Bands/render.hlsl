// Audio Bands / render - the drawing.
//
// Top: the live spectrum on a log-Hz axis, with each lane's band drawn as a shaded slab over it.
// The slab IS the set of bins that gets summed. Each band carries its threshold fader: a bar
// across the band and a grab tab on its right edge.
//
// Bottom: one strip per lane showing that lane's onset value at hop resolution with its threshold
// dashed across it and a tick where it fired.
//
// The point of putting the trace and the threshold on the same axes is that a missed hit becomes
// a thing you can see rather than a thing you guess at: the peak is either under the line or it
// is not.
//
// Colour, on the shared instrument palette: grey for everything at rest. The accent marks the two
// live things and nothing else - DETECTION (flux over its threshold, an accepted hit) down in the
// strips, and whatever is HELD (a band being moved or resized, a threshold being dragged) up in
// the spectrum - so the two never share a place. Hover lifts a band one value step, never a hue.
//
// The type, plate borders, lamps, readouts, hover inspector and keycap footer are recorded by
// layout.hlsl and drawn over this by the shared UI kit (ui.hlsl).
//
// LAYOUT: a Canvas at follow_panel resolution. The spectrum's extents are bands.hlsli's, the same
// functions events.hlsl hit-tests; the plates and strips derive from the live extent through
// bands_view.hlsli. There are no absolute pixel numbers here.

#include "bands.hlsli"
#include "../_shared/ui/il_core.hlsli"

StructuredBuffer<float4> Cols  : register(t0);
StructuredBuffer<float4> Bands : register(t1);
StructuredBuffer<float4> Det   : register(t2);
RWTexture2D<float4> OutputUAV  : register(u0);

#include "bands_view.hlsli"

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 p = float2(px) + 0.5;
    float2 R = _Resolution.xy;
    float  W = R.x;
    float  H = R.y;
    float  s = abS(R);

    float3 col = IL_FIELD;

    // The spectrum's own unit, from bands.hlsli: its extents and the grab zone are multiples of it.
    float u   = abUI(H);
    float lw  = max(1.0, u * 0.5);       // stroke width

    float specBot = floor(H * AB_SPEC_BOT);
    float plotBot = abPlotBot(H);
    float plotTop = abPlotTop(H);

    float4 hdr   = Cols[AB_COL_HDR];
    float  hzMax = hdr.y;
    float  hopDt = hdr.z;

    // What is held (events.hlsl's drag record) and, when nothing is, what the pointer is over.
    int    held    = abHeldLane();
    bool   heldBar = held >= 0 && abHeldBar();
    float2 ptr     = abPointer(R);
    int    hot     = (held < 0) ? abBandAt(ptr, R, hzMax) : -1;
    bool   hotBar  = hot >= 0 && abOnBar(ptr, (uint)hot, H);
    int    hotLane = (held < 0 && hot < 0) ? abLaneAt(ptr, R) : -1;

    // ======================= SPECTRUM =======================================
    if (p.y < specBot) {
        float4 sp = abSpecPlate(R);
        float  dPlate = ilSdBox(p, sp, IL_RADIUS * s);
        ilOver(col, IL_PANEL, ilFill(dPlate));
        bool inY = (p.y > plotTop && p.y < plotBot);
        if (inY) col = IL_WELL;

        // The octave ruler: a grid line through the plot, a tick into the foot where its label sits.
        [loop] for (int o = 0; o < 10; ++o) {
            float hz = abOctHz(o);
            if (hz > hzMax) break;
            float gx = abHzToX(hz, hzMax) * W;
            if (abs(p.x - gx) < 0.5) {
                if (inY) col = IL_GRID;
                else if (p.y >= plotBot && p.y < plotBot + 4.0 * u) col = IL_RULE;
            }
        }

        // Band slabs, washed in under the bars: the whole point is to see the signal inside the
        // band, not to cover it up.
        [loop] for (uint L = 0u; L < AB_LANES; ++L) {
            float4 b = Bands[L];
            if (b.z < 0.5 || b.y <= b.x || !inY) continue;
            float x0 = abHzToX(b.x, hzMax) * W;
            float x1 = abHzToX(b.y, hzMax) * W;
            if (p.x < x0 || p.x > x1) continue;
            bool moving = ((int)L == held) && !heldBar;
            bool lifted = ((int)L == held) || ((int)L == hot);
            ilOver(col, IL_INK, moving ? 0.10 : (lifted ? 0.065 : 0.035));
        }

        // One reduced column per real pixel, so the spectrum gains detail as the panel widens
        // instead of stretching a fixed-width picture across it. Past the reducer's capacity it
        // degrades to a stretch rather than to a frozen right-hand edge.
        float cw = min(W, (float)AB_COLS_MAX);
        uint  ci = (uint)clamp(floor(p.x / W * cw), 0.0, cw - 1.0);
        float4 cv = Cols[ci];
        float barTop = plotBot - cv.x * (plotBot - plotTop);
        float peakY  = plotBot - cv.y * (plotBot - plotTop);

        if (p.y >= barTop && p.y < plotBot) col = max(col, lerp(IL_RULE, IL_MID * 0.8, cv.x));
        if (abs(p.y - peakY) < lw && cv.y > 0.004) col = max(col, IL_MID);
        if (abs(p.y - plotBot) < lw) col = max(col, IL_RULE);

        // Band edges, the bracket rail and the threshold fader, over the bars. A held band takes
        // the accent; the band under the pointer is lifted one value step.
        [loop] for (uint L2 = 0u; L2 < AB_LANES; ++L2) {
            float4 b = Bands[L2];
            if (b.z < 0.5 || b.y <= b.x) continue;
            float x0 = abHzToX(b.x, hzMax) * W;
            float x1 = abHzToX(b.y, hzMax) * W;
            bool  isHeld = ((int)L2 == held);
            bool  isHot  = ((int)L2 == hot);
            bool  moving = isHeld && !heldBar;
            bool  inX    = (p.x >= x0 && p.x <= x1);

            if (inY && (abs(p.x - x0) < lw || abs(p.x - x1) < lw)) {
                col = moving ? IL_ACCENT : max(col, isHot || isHeld ? IL_MID : IL_RULE * 1.3);
            }
            if (inX && abs(p.y - plotTop) < lw * (moving ? 2.0 : 1.0)) {
                col = moving ? IL_ACCENT : max(col, isHot || isHeld ? IL_INK : IL_DIM);
            }

            // ---- threshold fader ----
            // A bar plus a tab on the band's right edge, sized so it is obviously grabbable. It is
            // a flux threshold; the axis behind it is level, and the two are not the same
            // quantity, so the bar is styled as a control (ink, the accent while it is dragged)
            // rather than as a level on the dB axis.
            float barY = abThreshToY(b.w, H);
            bool  bHeld = isHeld && heldBar;
            bool  bHot  = isHot && hotBar;
            if (inX && inY && abs(p.y - barY) < lw * (bHeld ? 2.0 : (bHot ? 1.5 : 1.0))) {
                col = bHeld ? IL_ACCENT : lerp(col, IL_INK, bHot ? 1.0 : 0.8);
            }
            float4 tab = float4(x1 - 6.5 * u, barY - 2.5 * u, x1, barY + 2.5 * u);
            float  dTab = ilSdBox(p, tab, 0.8 * u);
            if (dTab < 2.0) {
                ilOver(col, IL_FIELD, ilFill(dTab - 1.0));                   // a halo over busy bars
                ilOver(col, bHeld ? IL_ACCENT : (bHot ? IL_INK : IL_INK * 0.82), ilFill(dTab));
            }
        }

        OutputUAV[px] = float4(col, 1.0);
        return;
    }

    // ======================= TRACE STRIPS ===================================
    uint lane = 0u;
    [loop] for (uint l = 1u; l < AB_LANES; ++l) if (p.y >= abLaneRect(l, R).y) lane = l;
    float4 lr = abLaneRect(lane, R);
    ilOver(col, IL_PANEL, ilFill(ilSdBox(p, lr, IL_RADIUS * s)));

    float4 pr = abLanePlot(lane, R);
    if (!ilIn(p, pr)) {
        OutputUAV[px] = float4(col, 1.0);
        return;
    }
    col = IL_WELL;

    float4 B = Det[abStateB(lane)];
    uint  wIdx  = (uint)max(B.z, 0.0);
    float fs    = abFullScale(lane);

    // The lane in hand, pointed at in the spectrum, or pointed at here, reads one step brighter.
    bool  active = ((int)lane == held) || ((int)lane == hot) || ((int)lane == hotLane);
    float gTop = pr.y + 1.0;
    float gBot = pr.w - 1.0;

    // ---- the trace ----
    if (hopDt > 0.0) {
        float nShow = abTraceShow(hopDt);
        float plotW = pr.z - pr.x;
        float u0 = (p.x - pr.x) / plotW;
        float u1 = (p.x + 1.0 - pr.x) / plotW;

        // A column can cover more than one hop at long spans. Take the max, so a peak is never
        // lost between two pixels - losing it is precisely the failure that makes a threshold
        // impossible to place.
        int kA = (int)floor(u0 * nShow);
        int kB = min((int)floor(u1 * nShow), kA + 8);

        float flux = 0.0, thr = 0.0, fired = 0.0;
        [loop] for (int k = kA; k <= kB; ++k) {
            float fk = (float)wIdx - nShow + (float)k;
            if (fk < 0.0) continue;
            float4 tv = Det[abTraceAt(lane, (uint)fk)];
            flux  = max(flux, tv.x);
            thr   = max(thr, tv.y);
            fired = max(fired, tv.z);
        }

        float gh   = gBot - gTop;
        float fy   = gBot - saturate(flux / fs) * gh;
        float thrY = gBot - saturate(thr  / fs) * gh;

        if (p.y >= fy && p.y <= gBot) {
            bool over = (p.y < thrY);
            col = over ? IL_ACCENT * 0.85 : max(col, active ? IL_DIM * 0.95 : IL_RULE);
        }

        // Accepted-hit tick, full strip height.
        if (fired > 0.5) col = max(col, IL_ACCENT * 0.45);

        // Threshold line, dashed so it never reads as signal. The dash period scales too, or it
        // would close up into a solid line on a large panel.
        if (abs(p.y - thrY) < lw && frac((p.x - pr.x) / (10.0 * s)) < 0.55) {
            col = lerp(col, IL_INK, 0.8);
        }

        if (abs(p.y - gBot) < lw * 0.5) col = max(col, IL_EDGE);
    }

    OutputUAV[px] = float4(col, 1.0);
}
