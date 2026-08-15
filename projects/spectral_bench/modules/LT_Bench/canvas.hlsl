// LT_Bench / canvas.hlsl — the plan preview. TWO PROJECTIONS, one record buffer.
//
// Upper strip: the bench in millimetres, drawn as a draughtsman would draw an optical layout —
// true element profiles, the chief path, the apex angle called out, and every element that light
// never reached marked as such. That last one is the failure mode that matters here: a bench is
// a chain, and the way a chain breaks is that something stops being lit.
//
// Lower strip: the SPECTRAL RAIL. A plan cannot show what happened to each colour at each
// interaction, and it cannot show the axis this subject is actually organised along. Left half is
// an event ladder (wavelength x interaction); right half is the deviation profile, whose width IS
// the dispersion, printed in degrees.
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
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "layout.hlsli"

StructuredBuffer<BenchRec> Bench : register(t0);
StructuredBuffer<PathSeg>  Chief : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

#define CHIEF_LANES 32
#define CHIEF_STRIDE (CHIEF_LANES * LT_MAX_SEG)

static float3 gCol;
static float2 gP;
static float  gS;

void ink(float cov, float3 c) { gCol = lerp(gCol, c, saturate(cov)); }

float fillA(float d)            { return saturate(0.5 - d); }
float strokeA(float d, float w) { return saturate(0.5 - (abs(d) - w * 0.5)); }
float dashA(float d, float w, float along, float period)
{
    return strokeA(d, w) * step(0.5, frac(along / max(period, 1e-3)));
}

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * t);
}
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
    return strokeA((frac(u) - 0.5) * period * 0.7071, w);
}

// ---------------------------------------------------------------------------------------------
// Short names, as glyph runs. A diagram whose elements are unlabelled makes the reader learn a
// shape vocabulary before they can read anything.
// ---------------------------------------------------------------------------------------------
void kindName(int k, out int c0, out int c1, out int c2, out int c3, out int c4, out int c5)
{
    c0 = S_SP; c1 = S_SP; c2 = S_SP; c3 = S_SP; c4 = S_SP; c5 = S_SP;
    if      (k == EK_PRISM)   { c0=S_P; c1=S_R; c2=S_I; c3=S_S; c4=S_M; }
    else if (k == EK_MIRROR)  { c0=S_M; c1=S_I; c2=S_R; c3=S_R; c4=S_O; c5=S_R; }
    else if (k == EK_SLAB)    { c0=S_S; c1=S_L; c2=S_A; c3=S_B; }
    else if (k == EK_LENS)    { c0=S_L; c1=S_E; c2=S_N; c3=S_S; }
    else if (k == EK_SPLITTER){ c0=S_S; c1=S_P; c2=S_L; c3=S_I; c4=S_T; }
    else if (k == EK_SCREEN)  { c0=S_S; c1=S_C; c2=S_R; c3=S_E; c4=S_E; c5=S_N; }
    else                      { c0=S_B; c1=S_L; c2=S_O; c3=S_C; c4=S_K; }
}
void matName(int m, out int c0, out int c1, out int c2, out int c3, out int c4, out int c5)
{
    c0 = S_SP; c1 = S_SP; c2 = S_SP; c3 = S_SP; c4 = S_SP; c5 = S_SP;
    if      (m == GM_CROWN)   { c0=S_C; c1=S_R; c2=S_O; c3=S_W; c4=S_N; }
    else if (m == GM_FLINT)   { c0=S_F; c1=S_L; c2=S_I; c3=S_N; c4=S_T; }
    else if (m == GM_SILICA)  { c0=S_S; c1=S_I; c2=S_L; c3=S_I; c4=S_C; c5=S_A; }
    else if (m == GM_SAPPHIRE){ c0=S_S; c1=S_A; c2=S_P; c3=S_P; c4=S_H; }
    else if (m == GM_DIAMOND) { c0=S_D; c1=S_I; c2=S_A; c3=S_M; c4=S_N; c5=S_D; }
    else                      { c0=S_W; c1=S_A; c2=S_T; c3=S_E; c4=S_R; }
}

// Event -> a value on the grey ladder, plus whether it is an alarm or the accent event.
// EXIT is the accent because refraction OUT of the glass is the dispersing event: it is the
// thing the whole instrument is watching for.
float3 eventColour(int ev, float power)
{
    if (ev == EV_TIR || ev == EV_EXHAUST) return PT_ALARM;
    if (ev == EV_EXIT) return PT_ACCENT;
    float t = (ev == EV_EMIT) ? 0.30 : (ev == EV_ENTER) ? 0.55 : (ev == EV_MIRROR) ? 0.70
            : (ev == EV_FRESNEL) ? 0.40 : (ev == EV_SCREEN) ? 0.85 : (ev == EV_ABSORB) ? 0.15
            : 0.22;
    return ptRamp(t * saturate(0.35 + power));
}

// ---------------------------------------------------------------------------------------------

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 P = (float2)px + 0.5;
    gP = P;
    gCol = PT_FIELD;

    LtLayout L = ltLayout(_Resolution.xy);
    float s = L.s;
    gS = s;

    BenchRec H = Bench[LT_HEADER];
    int sel = (int)clamp(H.p0.x, -1.0, (float)LT_TOTAL);
    int nElem = (int)H.r1;
    int alarms = (int)H.z;
    int railEm = (int)clamp(H.dev, 0.0, (float)(LT_MAX_EMIT - 1));

    // =========================================================================================
    // Chief-path statistics. Read once, used by both strips, so the number printed in the header
    // and the curve drawn in the rail can never disagree.
    //
    // THE RAIL'S BLOCK ONLY. The chief buffer now carries one block per emitter, but a spread, an
    // event ladder and a deviation profile are readings of ONE beam: averaging them across
    // sources would print a number no beam on the bench actually produces. The plan strip draws
    // every block; everything in the rail — and the SPREAD in the header — is `Rail Source`.
    // =========================================================================================
    // The spread is the angle between the extreme wavelengths WHERE THEY END UP, so it is taken
    // from each lane's LAST live segment. Scanning every segment instead would fold in the
    // partial bend at the entry face and report a number nothing in the picture corresponds to.
    uint  railBase = (uint)railEm * (uint)CHIEF_STRIDE;
    float devMin = 1e9, devMax = -1e9;
    int   maxDepth = 1;
    bool  anyLive = false;
    [loop] for (uint li = 0u; li < (uint)CHIEF_LANES; ++li)
    {
        float lastDev = 0.0; bool laneLive = false;
        [loop] for (uint sgi = 0u; sgi < (uint)LT_MAX_SEG; ++sgi)
        {
            PathSeg g = Chief[railBase + li * (uint)LT_MAX_SEG + sgi];
            if (!ltSegLive(g)) break;
            maxDepth = max(maxDepth, (int)g.depth + 1);
            lastDev = g.dev; laneLive = true;
        }
        if (!laneLive) continue;
        anyLive = true;
        devMin = min(devMin, lastDev);
        devMax = max(devMax, lastDev);
    }
    if (!anyLive) { devMin = 0.0; devMax = 0.0; }
    float spreadDeg = degrees(devMax - devMin);

    // =========================================================================================
    // HEADER
    // =========================================================================================
    if (P.y < L.head.w + 4.0 * s)
    {
        float ty = L.head.y + 3.0 * s;
        ink(sui3TextLong(P, float2(L.head.x, ty), s * 1.0,
                         S_S,S_P,S_E,S_C,S_T,S_R,S_A,S_L,S_SP,S_B,S_E,S_N,
                         S_C,S_H,0,0,0,0,0,0,0,0,0,0), PT_INK);

        float rx = L.head.z;
        float ry = ty;
        // spread, in degrees, to one decimal — the reading this instrument exists to produce
        float w = sui3FixedWidth(s, 1);
        ink(sui3Fixed(P, float2(rx - w, ry), s, min(spreadDeg, 99.9), 1), PT_ACCENT);
        ink(sui3Text(P, float2(rx - w - sui3TextWidth(7, s), ry), s,
                     S_S,S_P,S_R,S_E,S_A,S_D,S_SP,0,0,0,0,0), PT_DIM);

        float rx2 = rx - w - sui3TextWidth(9, s) - 14.0 * s;
        ink(sui3DigitsRight(P, rx2, ry, s, nElem, 2), PT_MID);
        ink(sui3Text(P, float2(rx2 - sui3TextWidth(2, s) - sui3TextWidth(5, s), ry), s,
                     S_E,S_L,S_E,S_M,S_SP,0,0,0,0,0,0,0), PT_DIM);

        float rx3 = rx2 - sui3TextWidth(7, s) - 14.0 * s;
        if (alarms > 0)
        {
            ink(sui3DigitsRight(P, rx3, ry, s, alarms, 2), PT_ALARM);
            ink(sui3Text(P, float2(rx3 - sui3TextWidth(2, s) - sui3TextWidth(6, s), ry), s,
                         S_A,S_L,S_A,S_R,S_M,S_SP,0,0,0,0,0,0), PT_ALARM);
        }
        ink(sui3HairAt(P.y, L.head.w) * step(L.head.x, P.x) * step(P.x, L.head.z), PT_RULE * 0.7);
    }

    // =========================================================================================
    // BENCH PLAN
    // =========================================================================================
    if (P.y > L.planBox.y - 2.0 * s && P.y < L.planBox.w + 2.0 * s)
    {
        ink(sui3Frame(P, L.planBox) * 0.55, PT_RULE);
        ink(sui3Brackets(P, L.planBox, 9.0 * s), PT_DIM);

        // ---- millimetre graticule ------------------------------------------------------------
        // 25 mm fine, 100 mm coarse. A plan without a ruler is a sketch: every size and stand-off
        // on this bench is a real distance and the diagram should let you read it.
        if (ltInBox(L.plan, P))
        {
            float2 bp = ltPixToBench(L, P);
            float fine = ltFromMM(25.0);
            float2 gf = abs(frac(bp / fine + 0.5) - 0.5) * fine * L.scale;
            ink(saturate(0.55 - min(gf.x, gf.y)) * 0.75, PT_GRID);
            float coarse = ltFromMM(100.0);
            float2 gc = abs(frac(bp / coarse + 0.5) - 0.5) * coarse * L.scale;
            ink(saturate(0.55 - min(gc.x, gc.y)) * 0.85, PT_GRID * 2.1);
        }
        ink(sui3Frame(P, float4(L.plan.x, L.plan.y, L.plan.z, L.plan.w)) * 0.8, PT_RULE);

        // Everything below is CLIPPED to the bench. A draughtsman's frame clips: an element wider
        // than the bench is cut at the border rather than drawn across the whole strip.
        if (ltInBox(L.plan, P)) {

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

                    float d = sdSeg(P, a, b);
                    int evE = (int)g.evtEnd;
                    bool broken = (evE == EV_TIR) || (evE == EV_EXHAUST);

                    float3 c = edge ? ptSampleColour(ltWavelengthRGB(g.wl)) * 0.72 : PT_MID * 0.62;
                    float aa = fa;
                    if (broken) { c = PT_ALARM; aa = 1.0; }
                    float wgt = (edge ? 1.35 : 0.9) * s * (isRail ? 1.0 : 0.85);

                    if (evE == EV_ESCAPE)
                        ink(dashA(d, wgt, length(P - a), 7.0 * s) * (edge ? 0.9 : 0.45) * aa, c);
                    else
                        ink(strokeA(d, wgt) * (edge ? 0.95 : 0.62) * aa, c);

                    // A vertex where something happened. The interaction is the interesting part
                    // of a light path, so it gets a mark rather than being left as a change of
                    // slope.
                    if (sj == 0u) continue;
                    float dv = length(P - a);
                    ink(strokeA(dv - 2.0 * s, 0.9 * s) * 0.8 * fa, eventColour((int)g.evt, g.power));
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
                ink(fillA(d) * (off ? 0.10 : 0.20), ptSampleFill(ltWavelengthRGB(520.0)) * 0.55);
                if (off) ink(dashA(d, lw, length(P - A), 6.0 * s), col);
                else     ink(strokeA(d, lw), col);
                // The apex angle, called out where a draughtsman would put it.
                float2 mid = (B + C) * 0.5;
                float2 toM = normalize(mid - A);
                float ar = length(mid - A) * 0.30;
                float a0 = atan2(normalize(B - A).y, normalize(B - A).x);
                float a1 = atan2(normalize(C - A).y, normalize(C - A).x);
                ink(strokeA(sdArc(P, A, ar, min(a0, a1), max(a0, a1)), 0.9 * s) * 0.7, PT_DIM);
                float2 lab = A + toM * (ar + 4.0 * s) - float2(sui3TextWidth(3, s) * 0.5, 5.0 * s);
                ink(sui3Digits(P, lab, s, (int)round(degrees(R.r0)), 2), PT_DIM);
            }
            else if (k == EK_SLAB)
            {
                float2 rel = P - c;
                float2 lp = float2(dot(rel, pp), dot(rel, ax));
                float d = sdBoxC(lp, float2(0, 0), float2(hx, hy * 0.5));
                ink(fillA(d) * (off ? 0.08 : 0.16), ptSampleFill(ltWavelengthRGB(520.0)) * 0.5);
                ink(off ? dashA(d, lw, lp.x + lp.y, 6.0 * s) : strokeA(d, lw), col);
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
                ink(fillA(d) * (off ? 0.08 : 0.18), ptSampleFill(ltWavelengthRGB(520.0)) * 0.5);
                ink(off ? dashA(d, lw, dot(P - c, pp), 6.0 * s) : strokeA(d, lw), col);
            }
            else
            {
                // Planar family. What separates them is the EDGE CONDITION, so each gets one:
                // a mirror is hatched on its dead side, a splitter is dashed because it is half
                // there, a screen is ruled because it is a measuring surface, a block is solid.
                float2 e0 = c - pp * hx, e1 = c + pp * hx;
                float d = sdSeg(P, e0, e1);
                float along = dot(P - e0, pp);

                if (k == EK_SPLITTER) ink(dashA(d, lw * 1.2, along, 5.0 * s), col);
                else if (k == EK_BLOCK)
                {
                    float db = sdBoxC(float2(dot(P - c, pp), dot(P - c, ax)), 0.0.xx,
                                      float2(hx, max(hy, 2.0 * s)));
                    ink(fillA(db) * hatchA(P, 5.0 * s, 1.0 * s) * 0.85, col);
                    ink(strokeA(db, lw), col);
                }
                else ink(strokeA(d, lw * (k == EK_SCREEN ? 1.25 : 1.4)), col);

                if (k == EK_MIRROR)
                {
                    // Hatching behind the reflective face: the side light cannot get to.
                    float back = dot(P - c, ax);
                    float dh = max(d - 1.5 * s, max(back, -back - 5.0 * s));
                    ink(fillA(max(dh, abs(along) - hx)) * hatchA(P, 5.0 * s, 0.9 * s) * 0.55, PT_RULE);
                }
                if (k == EK_SCREEN)
                {
                    // Rulings, so a landing position can be read off the detector.
                    float t = frac(along / (8.0 * s));
                    float tick = strokeA((t - 0.5) * 8.0 * s, 0.9 * s)
                               * saturate(0.5 - (abs(dot(P - c, ax) + 3.0 * s) - 3.0 * s))
                               * step(abs(along), hx);
                    ink(tick * 0.5, PT_DIM);
                }
            }

            // Hand-edited: a small open square, the draughtsman's "this was moved".
            if (LtFlagF(R.flags, F_EDITED))
            {
                float2 m = c + float2(hx, -hx) * 0.0 + float2(0.0, 0.0);
                float dsq = sdBoxC(P, m, (2.6 * s).xx);
                ink(strokeA(dsq, 0.9 * s) * 0.85, isSel ? PT_ACCENT : PT_DIM);
            }
            // The bench failure mode, drawn: an element nothing reaches.
            if (unlit)
            {
                float dcx = min(sdSeg(P, c + (3.5 * s).xx, c - (3.5 * s).xx),
                                sdSeg(P, c + float2(3.5, -3.5) * s, c + float2(-3.5, 3.5) * s));
                ink(strokeA(dcx, 1.2 * s), PT_ALARM);
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
            ink(fillA(body) * 0.30, PT_RULE);
            ink(strokeA(body, 1.2 * s), col);
            ink(strokeA(sdSeg(P, c + pp * ap, c - pp * ap), 1.5 * s), col);

            float2 tip = c + ax * 15.0 * s;
            ink(strokeA(sdSeg(P, c, tip), 1.0 * s) * 0.9, col);
            ink(strokeA(sdSeg(P, tip, tip - ax * 4.0 * s + pp * 2.6 * s), 1.0 * s), col);
            ink(strokeA(sdSeg(P, tip, tip - ax * 4.0 * s - pp * 2.6 * s), 1.0 * s), col);
            if (isRail) ink(strokeA(length(P - c) - 10.0 * s, 0.9 * s) * 0.6, PT_ACCENT);
        }

        // ---- selection readout -------------------------------------------------------------------
        if (sel >= 0)
        {
            BenchRec R = Bench[sel];
            float2 anchor = float2(L.plan.x + 5.0 * s, L.plan.w - 24.0 * s);
            int a0,a1,a2,a3,a4,a5;
            if (R.role == ROLE_ELEMENT)
            {
                kindName((int)R.kind, a0,a1,a2,a3,a4,a5);
                ink(sui3Text(P, anchor, s, a0,a1,a2,a3,a4,a5,0,0,0,0,0,0), PT_ACCENT);
                if (ltIsGlass((int)R.kind))
                {
                    matName((int)R.tone, a0,a1,a2,a3,a4,a5);
                    ink(sui3Text(P, anchor + float2(sui3TextWidth(7, s), 0.0), s,
                                 a0,a1,a2,a3,a4,a5,0,0,0,0,0,0), PT_DIM);
                }
                // Size in millimetres and orientation in degrees. Real quantities, attached to
                // the thing they describe.
                float2 r2 = anchor + float2(0.0, 10.0 * s);
                ink(sui3Digits(P, r2, s, (int)round(ltToMM(R.p1.x * 2.0)), 3), PT_MID);
                ink(sui3Text(P, r2 + float2(sui3TextWidth(3, s), 0.0), s, S_M,S_M,0,0,0,0,0,0,0,0,0,0), PT_DIM);
                int deg = (int)round(degrees(R.hdg) + 720.0) % 360;
                ink(sui3Digits(P, r2 + float2(sui3TextWidth(7, s), 0.0), s, deg, 3), PT_MID);
                // A prism's angle is SET — it aimed itself once and then stopped. P re-aims it.
                if ((int)R.kind == EK_PRISM)
                    ink(sui3Text(P, r2 + float2(sui3TextWidth(11, s), 0.0), s,
                                 LtFlagF(R.flags, F_AIM) ? S_A : S_S,
                                 LtFlagF(R.flags, F_AIM) ? S_I : S_E,
                                 LtFlagF(R.flags, F_AIM) ? S_M : S_T,
                                 0,0,0,0,0,0,0,0,0),
                        LtFlagF(R.flags, F_AIM) ? PT_ACCENT : PT_DIM);
            }
            else
            {
                ink(sui3Text(P, anchor, s, S_S,S_O,S_U,S_R,S_C,S_E,0,0,0,0,0,0), PT_ACCENT);
                float2 r2 = anchor + float2(0.0, 10.0 * s);
                ink(sui3Digits(P, r2, s, (int)round(ltToMM(R.p1.x)), 3), PT_MID);
                ink(sui3Text(P, r2 + float2(sui3TextWidth(3, s), 0.0), s, S_M,S_M,0,0,0,0,0,0,0,0,0,0), PT_DIM);
            }
        }

        }   // end bench clip
    }

    // =========================================================================================
    // SPECTRAL RAIL
    // =========================================================================================
    if (P.y > L.railBox.y - 2.0 * s)
    {
        ink(sui3Frame(P, L.railBox) * 0.55, PT_RULE);

        // ---- wavelength axis, shared by both plots ---------------------------------------------
        [loop] for (int t = 0; t < 4; ++t)
        {
            float wl = 400.0 + 100.0 * (float)t;
            float y = ltWlToY(L.ladder, wl);
            ink(sui3HairAt(P.y, y) * step(L.ladder.x - 4.0 * s, P.x) * step(P.x, L.devplot.z) * 0.5, PT_GRID * 1.6);
            ink(sui3Digits(P, float2(L.railBox.x + 3.0 * s, y - 5.0 * s), s, (int)wl, 3), PT_DIM);
        }

        // ---- LEFT: the event ladder -------------------------------------------------------------
        ink(sui3Frame(P, L.ladder) * 0.5, PT_RULE * 0.8);
        ink(sui3Text(P, float2(L.ladder.x, L.railBox.y + 1.0 * s), s,
                     S_E,S_V,S_E,S_N,S_T,S_SP,S_L,S_A,S_D,S_D,S_E,S_R), PT_DIM);
        // WHICH source the rail is reading. The plan draws every fan, so the rail has to say which
        // of them these two plots belong to — and it says it in the same accent as the ring drawn
        // round that source's housing above, so the two are one reading rather than two labels.
        {
            float cy = L.railBox.y + 1.0 * s;
            ink(sui3DigitsRight(P, L.ladder.z, cy, s, railEm, 2), PT_ACCENT);
            ink(sui3Text(P, float2(L.ladder.z - sui3TextWidth(2, s) - sui3TextWidth(4, s), cy), s,
                         S_S,S_R,S_C,S_SP,0,0,0,0,0,0,0,0), PT_DIM);
        }

        if (ltInBox(float4(L.ladder.x - 1.0, L.ladder.y - 1.0, L.ladder.z + 1.0, L.ladder.w + 1.0), P))
        {
            float colW = (L.ladder.z - L.ladder.x) / (float)maxDepth;
            float rowH = (L.ladder.w - L.ladder.y) / (float)CHIEF_LANES;
            int col = (int)clamp(floor((P.x - L.ladder.x) / max(colW, 1e-3)), 0.0, (float)maxDepth - 1.0);
            // The ladder's rows run RED AT THE TOP, matching the wavelength axis beside it.
            int row = (int)clamp(floor((L.ladder.w - P.y) / max(rowH, 1e-3)), 0.0, (float)CHIEF_LANES - 1.0);

            PathSeg g = Chief[railBase + (uint)row * (uint)LT_MAX_SEG + (uint)col];
            float2 cc = float2(L.ladder.x + ((float)col + 0.5) * colW,
                               L.ladder.w - ((float)row + 0.5) * rowH);
            float2 hh = float2(colW * 0.5 - 1.0 * s, rowH * 0.5 - 0.35 * s);
            float d = sdBoxC(P, cc, max(hh, 0.4 * s));

            if (ltSegLive(g))
            {
                ink(fillA(d) * 0.92, eventColour((int)g.evtEnd, g.power));
                // Power carried, as a fill height inside the cell — so a cell can say "this
                // happened" and "how much light was left" at the same time.
                float ph = hh.y * 2.0 * saturate(g.power);
                float db = sdBoxC(P, float2(cc.x, cc.y + hh.y - ph * 0.5), float2(hh.x * 0.30, ph * 0.5));
                ink(fillA(db) * 0.55, PT_INK);
            }
            else ink(fillA(d) * 0.5, PT_WELL);
        }

        // Column captions: the interaction index.
        [loop] for (int cci = 0; cci < maxDepth && cci < LT_MAX_SEG; ++cci)
        {
            float colW = (L.ladder.z - L.ladder.x) / (float)maxDepth;
            float cx = L.ladder.x + ((float)cci + 0.5) * colW - sui3TextWidth(1, s) * 0.5;
            ink(sui3Digits(P, float2(cx, L.ladder.w + 1.5 * s), s, cci, 1), PT_DIM);
        }

        // ---- RIGHT: the deviation profile --------------------------------------------------------
        // x is total deviation in degrees, y is wavelength. The horizontal extent of this curve IS
        // the dispersion. Drawn in true spectral colour, because here the colour is the datum.
        ink(sui3Frame(P, L.devplot) * 0.5, PT_RULE * 0.8);
        ink(sui3Text(P, float2(L.devplot.x, L.railBox.y + 1.0 * s), s,
                     S_D,S_E,S_V,S_I,S_A,S_T,S_I,S_O,S_N,0,0,0), PT_DIM);

        float lo = degrees(devMin), hi = degrees(devMax);
        float pad = max((hi - lo) * 0.18, 1.5);
        lo -= pad; hi += pad;

        if (ltInBox(float4(L.devplot.x - 6.0 * s, L.devplot.y - 2.0 * s,
                           L.devplot.z + 2.0 * s, L.devplot.w + 12.0 * s), P))
        {
            // zero-deviation reference line, when it is in range
            if (lo < 0.0 && hi > 0.0)
            {
                float zx = lerp(L.devplot.x, L.devplot.z, saturate((0.0 - lo) / max(hi - lo, 1e-3)));
                ink(sui3HairAt(P.x, zx) * step(L.devplot.y, P.y) * step(P.y, L.devplot.w) * 0.6, PT_GRID * 2.0);
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

                float y = ltWlToY(L.devplot, wl);
                float x = lerp(L.devplot.x, L.devplot.z, saturate((degrees(dv) - lo) / max(hi - lo, 1e-3)));
                float3 c = ptSampleColour(ltWavelengthRGB(wl));
                if (endEv == EV_TIR || endEv == EV_EXHAUST) c = PT_ALARM;

                float rowH = (L.devplot.w - L.devplot.y) / (float)CHIEF_LANES;
                float d = sdBoxC(P, float2(x, y), float2(1.5 * s, max(rowH * 0.5, 0.6 * s)));
                ink(fillA(d), c);
            }

            // Range labels at the two ends: a plot with no numbers on its axis is a picture.
            ink(sui3Digits(P, float2(L.devplot.x, L.devplot.w + 1.5 * s), s,
                           (int)abs(round(lo)), 2), PT_DIM);
            ink(sui3DigitsRight(P, L.devplot.z, L.devplot.w + 1.5 * s, s, (int)abs(round(hi)), 2), PT_DIM);
        }
    }

    // =========================================================================================
    // FOOTER — the verbs.
    //
    // This node is an EDITOR, and an editor whose verbs are invisible is an editor nobody uses.
    // ADD and SOURCE are drawn at full ink because they are the two that turn a generated bench
    // into one you built; everything else is secondary and drawn as such.
    // =========================================================================================
    if (P.y > L.foot.y - 2.0 * s)
    {
        float fs = max(s - 1.0, 1.0);
        float adv = SUI3_ADVANCE * fs;
        float2 a = float2(L.foot.x, L.foot.y);
        float2 b = a + float2(0.0, 13.0 * fs);

        // row 1 — building the bench
        ink(sui3TextLong(P, a, fs,
                         S_A,S_SP,S_A,S_D,S_D,S_SP,S_SP,S_SP,S_S,S_SP,S_S,S_O,
                         S_U,S_R,S_C,S_E,0,0,0,0,0,0,0,0), PT_INK);
        ink(sui3TextLong(P, a + float2(adv * 18.0, 0.0), fs,
                         S_D,S_SP,S_R,S_E,S_M,S_O,S_V,S_E,S_SP,S_SP,S_SP,S_SP,
                         S_SP,S_0,S_SP,S_W,S_I,S_P,S_E,S_SP,S_SP,S_SP,0,0), PT_DIM);
        ink(sui3TextLong(P, a + float2(adv * 41.0, 0.0), fs,
                         S_K,S_SP,S_K,S_I,S_N,S_D,S_SP,S_SP,S_SP,S_M,S_SP,S_G,
                         S_L,S_A,S_S,S_S,S_SP,S_SP,S_SP,S_P,S_SP,S_A,S_U,S_T), PT_DIM);
        ink(sui3TextLong(P, a + float2(adv * 65.0, 0.0), fs,
                         S_O,S_SP,S_SP,S_SP,S_X,S_SP,S_O,S_N,S_SP,S_SP,S_SP,S_N,
                         S_SP,S_R,S_O,S_L,S_L,S_SP,S_SP,S_SP,S_R,S_SP,S_SP,S_SP), PT_DIM);

        // row 2 — the pointer
        ink(sui3TextLong(P, b, fs,
                         S_C,S_L,S_I,S_C,S_K,S_SP,S_P,S_I,S_C,S_K,S_SP,S_SP,
                         S_SP,S_D,S_R,S_A,S_G,S_SP,S_M,S_O,S_V,S_E,S_SP,S_SP), PT_DIM * 0.85);
        ink(sui3TextLong(P, b + float2(adv * 24.0, 0.0), fs,
                         S_SP,S_R,S_SP,S_D,S_R,S_A,S_G,S_SP,S_T,S_U,S_R,S_N,
                         S_SP,S_SP,S_SP,S_W,S_H,S_E,S_E,S_L,S_SP,S_S,S_I,S_Z), PT_DIM * 0.85);
        ink(sui3TextLong(P, b + float2(adv * 48.0, 0.0), fs,
                         S_E,S_SP,S_SP,S_SP,S_R,S_SP,S_R,S_E,S_S,S_E,S_E,S_D,
                         S_SP,S_SP,S_SP,S_C,S_SP,S_D,S_R,S_O,S_P,0,0,0), PT_DIM * 0.85);
    }

    OutputUAV[px] = float4(gCol, 1.0);
}
