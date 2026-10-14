// LT_Bench / canvas.hlsl — the plan preview's DRAWING. TWO PROJECTIONS, one record buffer.
//
// Upper plate: the bench in millimetres, drawn as a draughtsman would draw an optical layout —
// true element profiles, the chief path, the apex angle arc, and every element that light never
// reached marked as such. That last one is the failure mode that matters here: a bench is a chain,
// and the way a chain breaks is that something stops being lit.
//
// Lower plate: the SPECTRAL RAIL. A plan cannot show what happened to each colour at each
// interaction, and it cannot show the axis this subject is actually organised along. Left is an
// event ladder (wavelength x interaction); right is the deviation profile, whose width IS the
// dispersion.
//
// Only the drawing lives here. Every word and number — title, readouts, captions, axis labels, the
// apex angle, the selection readout, the inspector, the verbs — and every frame around a plate or a
// plot is recorded by layout.hlsl and drawn over this by the shared UI kit (ui.hlsl). Both go
// through ltLayout(), the same function plan.hlsl picks with.
//
// Instrument palette: mostly monochrome. Hue is spent on four things and each can be named —
// amber for the selection, red for a broken state, the two extreme wavelengths in the plan so the
// fan's envelope is legible among 32 grey hairlines, and true spectral colour inside the rail's
// plots, where the colour IS the measurement rather than decoration.
// The canvas reads both buffers but traces nothing, so it deliberately does NOT define LT_BENCH
// or LT_PATHS: it gets the record contract, the spectral colour and the geometry helpers, and
// the scene query and kernel are not compiled into it at all.
#include "../_shared/bench.hlsli"
#include "../_shared/optics.hlsli"
#include "../_shared/ui/il_core.hlsli"
#include "layout.hlsli"

StructuredBuffer<BenchRec> Bench : register(t0);
StructuredBuffer<PathSeg>  Chief : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);
#include "rail.hlsli"

static float3 gCol;
static float2 gP;
static float  gS;

void ink(float cov, float3 c) { gCol = lerp(gCol, c, saturate(cov)); }

float dashA(float d, float w, float along, float period)
{
    return ilStroke(d, w) * step(0.5, frac(along / max(period, 1e-3)));
}
// A one-pixel rule at a snapped coordinate: snap the coordinate, never the distance.
float hairAt(float p, float at) { return 1.0 - smoothstep(0.0, 1.0, abs(p - (floor(at) + 0.5))); }

float sdBoxC(float2 p, float2 c, float2 h)
{
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
float sdTri(float2 p, float2 a, float2 b, float2 c)
{
    // Signed distance to a triangle. Negative inside.
    float2 e0 = b - a, e1 = c - b, e2 = a - c;
    float2 v0 = p - a, v1 = p - b, v2 = p - c;
    float2 p0 = v0 - e0 * saturate(dot(v0, e0) / dot(e0, e0));
    float2 p1 = v1 - e1 * saturate(dot(v1, e1) / dot(e1, e1));
    float2 p2 = v2 - e2 * saturate(dot(v2, e2) / dot(e2, e2));
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(p0, p0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(p1, p1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(p2, p2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}
// An arc of a circle, for lens profiles and angle call-outs.
float sdArc(float2 p, float2 c, float r, float a0, float a1)
{
    float2 v = p - c;
    float a = atan2(v.y, v.x);
    float lo = min(a0, a1), hi = max(a0, a1);
    // bring a into [lo, lo+2pi)
    float aw = lo + (float)fmod(a - lo + LT_TAU * 4.0, LT_TAU);
    if (aw <= hi) return abs(length(v) - r);
    float2 e0 = c + float2(cos(a0), sin(a0)) * r;
    float2 e1 = c + float2(cos(a1), sin(a1)) * r;
    return min(length(p - e0), length(p - e1));
}

// Hatching, for the dead side of a mirror and the body of a blocker. Screen-aligned on purpose:
// it is chrome, not geometry, and it must read the same however the element is turned.
float hatchA(float2 p, float period, float w)
{
    float u = (p.x + p.y) / max(period, 1.0);
    return ilStroke((frac(u) - 0.5) * period * 0.7071, w);
}

// ---------------------------------------------------------------------------------------------

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 P = (float2)px + 0.5;
    gP = P;
    gCol = IL_FIELD;

    LtLayout L = ltLayout(_Resolution.xy);
    float s = L.s;
    gS = s;

    BenchRec H = Bench[LT_HEADER];
    int sel = (int)clamp(H.p0.x, -1.0, (float)LT_TOTAL);
    int railEm = (int)clamp(H.dev, 0.0, (float)(LT_MAX_EMIT - 1));

    // =========================================================================================
    // BENCH PLAN — a plate, and the bench itself inset in it as a well (layout.hlsl draws the
    // plate's edge, the bench's frame and every caption).
    // =========================================================================================
    float dPlan = ilSdBox(P, L.planBox, IL_RADIUS * s);
    if (dPlan < 1.0)
    {
        ink(ilFill(dPlan), IL_PANEL);

        // Everything below is CLIPPED to the bench. A draughtsman's frame clips: an element wider
        // than the bench is cut at the border rather than drawn across the whole plate.
        if (ltInBox(L.plan, P)) {

        ink(1.0, IL_WELL);

        // ---- millimetre graticule ------------------------------------------------------------
        // 25 mm fine, 100 mm coarse. A plan without a ruler is a sketch: every size and stand-off
        // on this bench is a real distance and the diagram should let you read it.
        {
            float2 bp = ltPixToBench(L, P);
            float fine = ltFromMM(25.0);
            float2 gf = abs(frac(bp / fine + 0.5) - 0.5) * fine * L.scale;
            ink(saturate(0.55 - min(gf.x, gf.y)) * 0.75, PT_GRID);
            float coarse = ltFromMM(100.0);
            float2 gc = abs(frac(bp / coarse + 0.5) - 0.5) * coarse * L.scale;
            ink(saturate(0.55 - min(gc.x, gc.y)) * 0.85, PT_GRID * 2.1);
        }

        // ---- the chief fans -------------------------------------------------------------------
        // 32 grey hairlines per source, plus the two EXTREME wavelengths in their own muted
        // colour. A fully monochrome fan is an unreadable tangle; a fully spectral one competes
        // with the program image. Two hues mark the envelope, which is the only thing grey
        // genuinely cannot say.
        //
        // EVERY SOURCE, not just the rail's. A plan that draws one beam and leaves the other
        // housings sitting in the dark is not describing the bench in front of it — and multiple
        // sources is exactly when a plan earns its keep, because that is when you cannot tell
        // from the program image alone which beam went where.
        //
        // The rail's source is drawn LAST and at full weight, so wherever fans cross it wins the
        // ink and stays identifiable as the one the ladder below is reading. The others are the
        // same drawing at about half strength: still legible, never mistaken for the subject.
        // An ALARM is never dimmed — a beam that dies is worth the same attention on any source.
        uint nFan = (plan_fans < 0.5) ? 1u : (uint)LT_MAX_EMIT;
        [loop] for (uint oi = 0u; oi < nFan; ++oi)
        {
            // Draw order: everything else first, the rail's source last.
            uint em = (nFan == 1u || oi + 1u == nFan) ? (uint)railEm
                    : ((oi < (uint)railEm) ? oi : oi + 1u);

            BenchRec FE = Bench[LT_EMIT_BASE + em];
            if (FE.role != ROLE_EMITTER || FE.active < 0.5) continue;

            bool  isRail = ((int)em == railEm);
            float fa = isRail ? 1.0 : 0.5;
            uint  fanBase = em * (uint)CHIEF_STRIDE;

            [loop] for (uint ci = 0u; ci < (uint)CHIEF_LANES; ++ci)
            {
                bool edge = (ci == 0u) || (ci == (uint)CHIEF_LANES - 1u);
                [loop] for (uint sj = 0u; sj < (uint)LT_MAX_SEG; ++sj)
                {
                    PathSeg g = Chief[fanBase + ci * (uint)LT_MAX_SEG + sj];
                    if (!ltSegLive(g)) break;
                    float2 a = ltBenchToPix(L, g.a);
                    float2 b = ltBenchToPix(L, g.b);
                    float2 lo = min(a, b) - 3.0 * s, hi = max(a, b) + 3.0 * s;
                    if (P.x < lo.x || P.x > hi.x || P.y < lo.y || P.y > hi.y) continue;

                    float d = ilSdSeg(P, a, b);
                    int evE = (int)g.evtEnd;
                    bool broken = (evE == EV_TIR) || (evE == EV_EXHAUST);

                    float3 c = edge ? ptSampleColour(ltWavelengthRGB(g.wl)) * 0.72 : PT_MID * 0.62;
                    float aa = fa;
                    if (broken) { c = PT_ALARM; aa = 1.0; }
                    float wgt = (edge ? 1.35 : 0.9) * s * (isRail ? 1.0 : 0.85);

                    if (evE == EV_ESCAPE)
                        ink(dashA(d, wgt, length(P - a), 7.0 * s) * (edge ? 0.9 : 0.45) * aa, c);
                    else
                        ink(ilStroke(d, wgt) * (edge ? 0.95 : 0.62) * aa, c);

                    // A vertex where something happened. The interaction is the interesting part
                    // of a light path, so it gets a mark rather than being left as a change of
                    // slope.
                    if (sj == 0u) continue;
                    float dv = length(P - a);
                    ink(ilStroke(dv - 2.0 * s, 0.9 * s) * 0.8 * fa, eventColour((int)g.evt, g.power));
                }
            }
        }

        // ---- elements ---------------------------------------------------------------------------
        [loop] for (uint ei = 0u; ei < (uint)LT_MAX_ELEM; ++ei)
        {
            uint idx = (uint)LT_ELEM_BASE + ei;
            BenchRec R = Bench[idx];
            if (R.role != ROLE_ELEMENT || R.active < 0.5) continue;

            int k = (int)R.kind;
            bool isSel = ((int)idx == sel);
            bool off   = LtFlagF(R.flags, F_OFF);
            bool unlit = LtFlagF(R.flags, F_UNLIT) && !off;
            bool alarm = LtFlagF(R.flags, F_ALARM);

            float2 c = ltBenchToPix(L, R.p0);
            float rad = ltBenchToPixR(L, max(R.p1.x, R.p1.y) * 1.6) + 14.0 * s;
            if (length(P - c) > rad) continue;

            float3 col = isSel ? PT_ACCENT : (alarm ? PT_ALARM : (unlit || off ? PT_RULE : PT_INK));
            float lw = isSel ? 1.7 * s : 1.15 * s;

            float2 ax = ltDir(R.hdg);
            float2 pp = ltPerp(ax);
            float hx = ltBenchToPixR(L, R.p1.x);
            float hy = ltBenchToPixR(L, max(R.p1.y, 0.004));

            if (k == EK_PRISM)
            {
                float2 pa, pb, pc;
                ltPrismVerts(R.p0, R.hdg, max(R.p1.x, 1e-4), R.r0, pa, pb, pc);
                float2 A = ltBenchToPix(L, pa), B = ltBenchToPix(L, pb), C = ltBenchToPix(L, pc);
                float d = sdTri(P, A, B, C);
                // Glass is drawn as a body with an INTERIOR, not an outline: a bare triangle
                // reads as a symbol, a filled one reads as a thing light has to get through.
                ink(ilFill(d) * (off ? 0.10 : 0.20), ptSampleFill(ltWavelengthRGB(520.0)) * 0.55);
                if (off) ink(dashA(d, lw, length(P - A), 6.0 * s), col);
                else     ink(ilStroke(d, lw), col);
                // The apex angle's arc, where a draughtsman would put it (its number is type).
                float2 mid = (B + C) * 0.5;
                float ar = length(mid - A) * 0.30;
                float a0 = atan2(normalize(B - A).y, normalize(B - A).x);
                float a1 = atan2(normalize(C - A).y, normalize(C - A).x);
                ink(ilStroke(sdArc(P, A, ar, min(a0, a1), max(a0, a1)), 0.9 * s) * 0.7, PT_DIM);
            }
            else if (k == EK_SLAB)
            {
                float2 rel = P - c;
                float2 lp = float2(dot(rel, pp), dot(rel, ax));
                float d = sdBoxC(lp, float2(0, 0), float2(hx, hy * 0.5));
                ink(ilFill(d) * (off ? 0.08 : 0.16), ptSampleFill(ltWavelengthRGB(520.0)) * 0.5);
                ink(off ? dashA(d, lw, lp.x + lp.y, 6.0 * s) : ilStroke(d, lw), col);
            }
            else if (k == EK_LENS)
            {
                float R0 = max(R.r0, 1e-3);
                float th = clamp(R.p1.y, 1e-4, 1.98 * R0);
                float off2 = R0 - th * 0.5;
                float2 c1 = ltBenchToPix(L, R.p0 - ax * off2);
                float2 c2 = ltBenchToPix(L, R.p0 + ax * off2);
                float rp = ltBenchToPixR(L, R0);
                float ha = ltBenchToPixR(L, min(ltLensAperture(R0, th), max(R.p1.x, 1e-4)));
                float d = max(max(length(P - c1) - rp, length(P - c2) - rp),
                              abs(dot(P - c, pp)) - ha);
                ink(ilFill(d) * (off ? 0.08 : 0.18), ptSampleFill(ltWavelengthRGB(520.0)) * 0.5);
                ink(off ? dashA(d, lw, dot(P - c, pp), 6.0 * s) : ilStroke(d, lw), col);
            }
            else
            {
                // Planar family. What separates them is the EDGE CONDITION, so each gets one:
                // a mirror is hatched on its dead side, a splitter is dashed because it is half
                // there, a screen is ruled because it is a measuring surface, a block is solid.
                float2 e0 = c - pp * hx, e1 = c + pp * hx;
                float d = ilSdSeg(P, e0, e1);
                float along = dot(P - e0, pp);

                if (k == EK_SPLITTER) ink(dashA(d, lw * 1.2, along, 5.0 * s), col);
                else if (k == EK_BLOCK)
                {
                    float db = sdBoxC(float2(dot(P - c, pp), dot(P - c, ax)), 0.0.xx,
                                      float2(hx, max(hy, 2.0 * s)));
                    ink(ilFill(db) * hatchA(P, 5.0 * s, 1.0 * s) * 0.85, col);
                    ink(ilStroke(db, lw), col);
                }
                else ink(ilStroke(d, lw * (k == EK_SCREEN ? 1.25 : 1.4)), col);

                if (k == EK_MIRROR)
                {
                    // Hatching behind the reflective face: the side light cannot get to.
                    float back = dot(P - c, ax);
                    float dh = max(d - 1.5 * s, max(back, -back - 5.0 * s));
                    ink(ilFill(max(dh, abs(along) - hx)) * hatchA(P, 5.0 * s, 0.9 * s) * 0.55, PT_RULE);
                }
                if (k == EK_SCREEN)
                {
                    // Rulings, so a landing position can be read off the detector.
                    float t = frac(along / (8.0 * s));
                    float tick = ilStroke((t - 0.5) * 8.0 * s, 0.9 * s)
                               * saturate(0.5 - (abs(dot(P - c, ax) + 3.0 * s) - 3.0 * s))
                               * step(abs(along), hx);
                    ink(tick * 0.5, PT_DIM);
                }
            }

            // Hand-edited: a small open square, the draughtsman's "this was moved".
            if (LtFlagF(R.flags, F_EDITED))
            {
                float dsq = sdBoxC(P, c, (2.6 * s).xx);
                ink(ilStroke(dsq, 0.9 * s) * 0.85, isSel ? PT_ACCENT : PT_DIM);
            }
            // The bench failure mode, drawn: an element nothing reaches.
            if (unlit)
            {
                float dcx = min(ilSdSeg(P, c + (3.5 * s).xx, c - (3.5 * s).xx),
                                ilSdSeg(P, c + float2(3.5, -3.5) * s, c + float2(-3.5, 3.5) * s));
                ink(ilStroke(dcx, 1.2 * s), PT_ALARM);
            }
        }

        // ---- emitters ---------------------------------------------------------------------------
        [loop] for (uint mi = 0u; mi < (uint)LT_MAX_EMIT; ++mi)
        {
            uint idx = (uint)LT_EMIT_BASE + mi;
            BenchRec E = Bench[idx];
            if (E.role != ROLE_EMITTER || E.active < 0.5) continue;
            float2 c = ltBenchToPix(L, E.p0);
            if (length(P - c) > 34.0 * s) continue;

            bool isSel = ((int)idx == sel);
            bool isRail = ((int)mi == railEm);
            float3 col = isSel ? PT_ACCENT : (isRail ? PT_INK : PT_MID);

            float2 ax = ltDir(E.hdg), pp = ltPerp(ax);
            float ap = ltBenchToPixR(L, max(E.p1.x, 1e-4)) * 0.5;

            // A source housing with a mouth: an emitter that is just an arrow does not read as
            // an object, and its aperture is a real dimension the beam width comes from.
            float2 lp = float2(dot(P - c, ax), dot(P - c, pp));
            float body = sdBoxC(lp, float2(-5.0 * s, 0.0), float2(5.0 * s, max(ap, 3.0 * s)));
            ink(ilFill(body) * 0.30, PT_RULE);
            ink(ilStroke(body, 1.2 * s), col);
            ink(ilStroke(ilSdSeg(P, c + pp * ap, c - pp * ap), 1.5 * s), col);

            float2 tip = c + ax * 15.0 * s;
            ink(ilStroke(ilSdSeg(P, c, tip), 1.0 * s) * 0.9, col);
            ink(ilStroke(ilSdSeg(P, tip, tip - ax * 4.0 * s + pp * 2.6 * s), 1.0 * s), col);
            ink(ilStroke(ilSdSeg(P, tip, tip - ax * 4.0 * s - pp * 2.6 * s), 1.0 * s), col);
            if (isRail) ink(ilStroke(length(P - c) - 10.0 * s, 0.9 * s) * 0.6, PT_ACCENT);
        }

        }   // end bench clip
    }

    // =========================================================================================
    // SPECTRAL RAIL — a plate with the two plots inset as wells.
    // =========================================================================================
    float dRail = ilSdBox(P, L.railBox, IL_RADIUS * s);
    if (dRail < 1.0)
    {
        ink(ilFill(dRail), IL_PANEL);
        ink(ilFill(ilSdBox(P, L.ladder, 1.5 * s)), IL_WELL);
        ink(ilFill(ilSdBox(P, L.devplot, 1.5 * s)), IL_WELL);

        // ---- the lane axis, shared by both plots: a rule on each row the type labels -----------
        BenchRec RE = Bench[LT_EMIT_BASE + (uint)railEm];
        float4 aw, ar;
        uint na = ltRailAxis((int)clamp(RE.tone, 0.0, (float)(SP_COUNT - 1)), RE.wl0, RE.wl1, aw, ar);
        [loop] for (uint t = 0u; t < na; ++t)
        {
            float y = ltRailRowY(L.ladder, ar[t]);
            ink(hairAt(P.y, y) * step(L.ladder.x - 4.0 * s, P.x) * step(P.x, L.devplot.z) * 0.5, PT_GRID * 1.6);
        }

        // The rail's readings, only where a plot needs them — not for every pixel of the canvas.
        bool inLadder = ltInBox(float4(L.ladder.x - 1.0, L.ladder.y - 1.0, L.ladder.z + 1.0, L.ladder.w + 1.0), P);
        bool inDev = ltInBox(float4(L.devplot.x - 6.0 * s, L.devplot.y - 2.0 * s,
                                    L.devplot.z + 2.0 * s, L.devplot.w + 12.0 * s), P);
        if (inLadder || inDev)
        {
            uint railBase = (uint)railEm * (uint)CHIEF_STRIDE;
            RailStats st = ltRailStats(railBase);

            // ---- LEFT: the event ladder ---------------------------------------------------------
            if (inLadder)
            {
                float2 cell = ltLadderCell(L.ladder, st.maxDepth);
                float colW = cell.x, rowH = cell.y;
                int col = (int)clamp(floor((P.x - L.ladder.x) / max(colW, 1e-3)), 0.0, (float)st.maxDepth - 1.0);
                // The ladder's rows run RED AT THE TOP, matching the wavelength axis beside it.
                int row = (int)clamp(floor((L.ladder.w - P.y) / max(rowH, 1e-3)), 0.0, (float)CHIEF_LANES - 1.0);

                PathSeg g = Chief[railBase + (uint)row * (uint)LT_MAX_SEG + (uint)col];
                float2 cc = float2(L.ladder.x + ((float)col + 0.5) * colW,
                                   L.ladder.w - ((float)row + 0.5) * rowH);
                float2 hh = float2(colW * 0.5 - 1.0 * s, rowH * 0.5 - 0.35 * s);
                float d = sdBoxC(P, cc, max(hh, 0.4 * s));

                if (ltSegLive(g))
                {
                    ink(ilFill(d) * 0.92, eventColour((int)g.evtEnd, g.power));
                    // Power carried, as a fill height inside the cell — so a cell can say "this
                    // happened" and "how much light was left" at the same time.
                    float ph = hh.y * 2.0 * saturate(g.power);
                    float db = sdBoxC(P, float2(cc.x, cc.y + hh.y - ph * 0.5), float2(hh.x * 0.30, ph * 0.5));
                    ink(ilFill(db) * 0.55, PT_INK);
                }
                else ink(ilFill(d) * 0.6, IL_PANEL);
            }

            // ---- RIGHT: the deviation profile -----------------------------------------------------
            // x is total deviation in degrees, y is the lane - the ladder's row, so a mark sits level
            // with its own ladder row. The horizontal extent of this curve IS the dispersion. Drawn
            // in true spectral colour, because here the colour is the datum.
            if (inDev)
            {
                float lo, hi;
                ltDevRange(st, lo, hi);

                // zero-deviation reference line, when it is in range
                if (lo < 0.0 && hi > 0.0)
                {
                    float zx = ltDevToX(L.devplot, 0.0, lo, hi);
                    ink(hairAt(P.x, zx) * step(L.devplot.y, P.y) * step(P.y, L.devplot.w) * 0.6, PT_GRID * 2.0);
                }

                [loop] for (uint di = 0u; di < (uint)CHIEF_LANES; ++di)
                {
                    // The LAST live segment of a lane carries its final deviation.
                    float dv = 0.0; float wl = 0.0; bool live = false; int endEv = EV_EMIT;
                    [loop] for (uint dj = 0u; dj < (uint)LT_MAX_SEG; ++dj)
                    {
                        PathSeg g = Chief[railBase + di * (uint)LT_MAX_SEG + dj];
                        if (!ltSegLive(g)) break;
                        dv = g.dev; wl = g.wl; live = true; endEv = (int)g.evtEnd;
                    }
                    if (!live) continue;

                    float y = ltRailRowY(L.devplot, (float)di);
                    float x = ltDevToX(L.devplot, degrees(dv), lo, hi);
                    float3 c = ptSampleColour(ltWavelengthRGB(wl));
                    if (endEv == EV_TIR || endEv == EV_EXHAUST) c = PT_ALARM;

                    float rowH = (L.devplot.w - L.devplot.y) / (float)CHIEF_LANES;
                    float d = sdBoxC(P, float2(x, y), float2(1.5 * s, max(rowH * 0.5, 0.6 * s)));
                    ink(ilFill(d), c);
                }
            }
        }
    }

    OutputUAV[px] = float4(gCol, 1.0);
}
