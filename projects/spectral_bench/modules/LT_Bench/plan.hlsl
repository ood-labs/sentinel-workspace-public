// LT_Bench / plan.hlsl — the plan authority for spectral_bench.
//
// Single-threaded on purpose. The layout is a CHAIN — element i is placed on the beam leaving
// element i-1 — so it is inherently sequential, and the viewport event queue has to be reduced
// in order. 31 records is nothing next to any render pass.
//
// FOUR STAGES EVERY COOK, and the order is load-bearing:
//   1. regenerate, but only if the SIGNATURE changed  -> then commit the signature immediately
//   2. apply this cook's viewport events (which may bump the salt, invalidating the signature)
//   3. RESOLVE: walk the chief ray, re-solve every auto prism to minimum deviation, and mark
//      what light actually reached
//   4. header writeback
//
// Committing the signature in stage 1 rather than at the end is what makes the R key work: if it
// were written after stage 2, a reseed would overwrite the salt AND the signature in the same
// cook, the next cook would find them agreeing, and the reseed would silently do nothing.
// Declare the buffer FIRST, point the kernel's macro at it, then include the physics — SM 5.0
// cannot pass a resource as a function argument, so the shared code reaches it by name.
#include "../_shared/bench.hlsli"
RWStructuredBuffer<BenchRec> Bench : register(u0);
#define LT_BENCH Bench
#include "../_shared/optics.hlsli"
#include "layout.hlsli"

// Bump whenever the GENERATION ALGORITHM changes. Shader edits are invisible to the signature —
// without a bump a recompile keeps serving the previously generated bench and the change appears
// to have done nothing at all.
#define PLAN_VERSION 4

#define CHIEF_MAX 14
#define WL_D 589.3          // the sodium d-line: the chief wavelength, by convention

// ---------------------------------------------------------------------------------------------
// TRANSCRIPTION. variation = 0 reproduces exactly this, so the reference can never be lost.
//
// The reference is a steep beam from the lower left, one heavy-flint prism sitting at minimum
// deviation, and a floor the fan grazes on its way out of frame. The floor IS the photograph's
// backdrop: the fan only reads as a spectrum because it lands on something.
// ---------------------------------------------------------------------------------------------
static const float2 REF_EMIT_POS = float2(0.060, 0.505);
static const float  REF_EMIT_HDG = -0.800;      // up and to the right, ~46 degrees
static const float  REF_PRISM_AT = 0.315;       // distance along the beam to the prism centroid
static const float  REF_PRISM_SIDE = 0.150;
static const float2 REF_FLOOR_POS = float2(0.560, 0.541);
static const float  REF_FLOOR_HALF = 0.440;

// ---------------------------------------------------------------------------------------------
// Angle families. Deflections that share a step read as a designed bench; deflections drawn
// freely read as scatter, however good each element is. Snap LAST and snap AGAIN before anything
// is derived from the heading — the average of two snapped angles is not snapped.
// ---------------------------------------------------------------------------------------------
float ltAngleStep(int fam)
{
    return (fam <= 0) ? 0.0
         : (fam == 1) ? (LT_PI * 0.5)
         : (fam == 2) ? (LT_PI / 3.0)
         : (fam == 3) ? (LT_PI * 0.25)
                      : (LT_PI / 6.0);
}
float ltSnapAngle(float a, float step, float phase)
{
    return (step <= 1e-5) ? a : (round((a - phase) / step) * step + phase);
}

// ---------------------------------------------------------------------------------------------
// The cast, as CATEGORY WEIGHTS rather than a fixed table.
//
// "Fewer mirrors" and "no beam splitters" are continuous asks, and the only way to honour "none
// of these" against a fixed sequence is to refuse the draw and take another from the categories
// still wanted. At 1.0 across the board the preset behaves exactly as authored.
// ---------------------------------------------------------------------------------------------
int ltCategoryOf(int kind)
{
    if (kind == EK_PRISM)  return 0;
    if (kind == EK_MIRROR) return 1;
    if (kind == EK_SLAB || kind == EK_LENS) return 2;
    return 3;   // splitter / block
}

int ltDrawKind(uint h, float wP, float wM, float wO, float wC)
{
    // Rejection and redraw, eight attempts, then the most neutral category. A muted set must
    // never produce an undefined element.
    [loop] for (uint a = 0u; a < 8u; ++a)
    {
        int k = (int)(ltRnd(h, 100u + a) * 4.999);   // 0..4 over PRISM/MIRROR/SLAB/LENS/SPLITTER
        int kind = (k == 0) ? EK_PRISM : (k == 1) ? EK_MIRROR : (k == 2) ? EK_SLAB
                 : (k == 3) ? EK_LENS : EK_SPLITTER;
        int cat = ltCategoryOf(kind);
        float w = (cat == 0) ? wP : (cat == 1) ? wM : (cat == 2) ? wO : wC;
        if (ltRnd(h, 200u + a) < saturate(w)) return kind;
    }
    return EK_PRISM;   // a bench with no prism is not this bench
}

// ---------------------------------------------------------------------------------------------
// Chain templates. Exploration axes shipped as a permanent enum, never as throwaway variants.
// Each returns the kind, the material, the size fraction and the desired deflection for link i.
// ---------------------------------------------------------------------------------------------
void ltTemplateLink(int preset, uint i, uint n, uint salt,
                    out int kind, out int mat, out float sizeF, out float devWant, out float dist)
{
    kind = EK_PRISM; mat = GM_FLINT; sizeF = 1.0; devWant = 1.0; dist = 0.34;

    if (preset == 1)          // Cascade — the spectrum split, and split again, by three glasses
    {
        kind = (i == n - 1u) ? EK_SCREEN : EK_PRISM;
        mat  = (i == 0u) ? GM_FLINT : ((i == 1u) ? GM_CROWN : GM_SAPPHIRE);
        sizeF = 1.0 - 0.18 * (float)i;
        devWant = (i % 2u == 0u) ? 1.0 : -1.0;
        dist = 0.30 - 0.03 * (float)i;
    }
    else if (preset == 2)     // Cavity — mirrors folding the path back on itself around a prism
    {
        kind = (i == 1u) ? EK_PRISM : ((i == n - 1u) ? EK_SCREEN : EK_MIRROR);
        mat  = GM_FLINT;
        sizeF = (kind == EK_MIRROR) ? 0.85 : 1.0;
        devWant = (i % 2u == 0u) ? -1.0 : 1.0;
        dist = 0.30;
    }
    else if (preset == 3)     // Battery — a splitter feeding two prisms, then a wall
    {
        kind = (i == 0u) ? EK_SPLITTER : ((i == n - 1u) ? EK_SCREEN : EK_PRISM);
        mat  = (i % 2u == 0u) ? GM_FLINT : GM_DIAMOND;
        sizeF = 0.9;
        devWant = 1.0;
        dist = 0.26;
    }
    else                      // Reference
    {
        kind = (i == 0u) ? EK_PRISM : EK_SCREEN;
        mat  = (int)clamp((float)glass_material, 0.0, (float)(GM_COUNT - 1));
        sizeF = 1.0;
        devWant = 1.0;
        dist = (i == 0u) ? REF_PRISM_AT : 0.40;
    }
}

// Orientation that makes an element deflect the arriving ray by `dev`.
// For a PRISM the deflection is NOT free — the physics chooses it and we only choose the side.
float ltSolveHdg(int kind, float inAngle, float dev, float apex, float nd)
{
    if (kind == EK_PRISM) return ltPrismMinDevHdg(inAngle, apex, nd, dev >= 0.0 ? 1.0 : -1.0);
    if (kind == EK_MIRROR || kind == EK_SPLITTER)
    {
        // The normal bisects the incoming and outgoing directions.
        float2 din = ltDir(inAngle);
        float2 dout = ltDir(inAngle + dev);
        float2 nn = normalize(dout - din);
        return atan2(nn.y, nn.x);
    }
    if (kind == EK_SCREEN || kind == EK_BLOCK) return inAngle + LT_PI;   // face the beam
    return inAngle;                                                       // slab / lens: on axis
}

// Default geometry per kind, sized against the throw it sits in rather than by a parallel
// parameter, so one Throw control moves the whole bench coherently.
void ltDefaultSize(int kind, float throwLen, float sizeF, float apex,
                   out float2 p1, out float r0, out float r1)
{
    float base = clamp(throwLen * 0.46, 0.045, 0.24) * sizeF;
    p1 = float2(base, base * 0.5);
    r0 = 1.0; r1 = 1.0;

    if (kind == EK_PRISM)        { p1 = float2(base, 0.0);              r0 = apex; r1 = 1.0; }
    else if (kind == EK_MIRROR)  { p1 = float2(base * 1.05, base*0.09); r0 = 0.94; }
    else if (kind == EK_SLAB)    { p1 = float2(base * 0.85, base*0.62); }
    else if (kind == EK_LENS)    { p1 = float2(base * 0.75, base*0.34); r0 = base * 1.55; }
    else if (kind == EK_SPLITTER){ p1 = float2(base * 0.95, base*0.05); r0 = 0.42; }
    else if (kind == EK_SCREEN)  { p1 = float2(min(base * 2.2, 0.34), base*0.05); r1 = 1.0; }
    else if (kind == EK_BLOCK)   { p1 = float2(base * 0.55, base*0.16); }
}

// ---------------------------------------------------------------------------------------------
// Signature. STRUCTURAL parameters only. Appearance and physics-look parameters (dispersion,
// screen gain, rail target) must stay out, or every look tweak wipes the user's layout work.
// ---------------------------------------------------------------------------------------------
uint ltSignature(uint salt)
{
    uint s = ltHashU((uint)(PLAN_VERSION * 7919));
    s = ltHash2(s, (uint)(layout_preset + 0.5));
    s = ltHash2(s, (uint)(variation * 4096.0));
    s = ltHash2(s, (uint)(seed * 64.0));
    s = ltHash2(s, (uint)(chain_len + 0.5));
    s = ltHash2(s, (uint)(throw_scale * 2048.0));
    s = ltHash2(s, (uint)(angle_family + 0.5));
    s = ltHash2(s, (uint)(emitter_count + 0.5));
    s = ltHash2(s, (uint)(beam_profile + 0.5));
    s = ltHash2(s, (uint)(beam_shape + 0.5));
    s = ltHash2(s, (uint)(glass_material + 0.5));
    s = ltHash2(s, (uint)(prism_apex * 64.0));
    s = ltHash2(s, (uint)(prism_size * 4096.0));
    // THE CAST WEIGHTS ONLY BITE AT variation > 0 — they are consumed solely by the kind draw,
    // which is gated on it. Left in the signature unconditionally they still invalidate the layout,
    // so nudging a slider that provably cannot change anything tore down and rebuilt the whole
    // generated bench. A parameter must not be able to destroy work it has no effect on.
    if (variation > 0.0)
    {
        s = ltHash2(s, (uint)(w_prism * 1024.0));
        s = ltHash2(s, (uint)(w_mirror * 1024.0));
        s = ltHash2(s, (uint)(w_optic * 1024.0));
        s = ltHash2(s, (uint)(w_control * 1024.0));
        s = ltHash2(s, (uint)(fit_frame * 1024.0));
    }
    s = ltHash2(s, salt);
    return s;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x != 0u) return;

    gDispGain = dispersion;

    // ---- header, sanitized on read -----------------------------------------------------------
    // A persistent buffer arrives from disk, from an undo payload, or uninitialised, and any of
    // those can carry values this code never wrote. Everything below is bounded before use.
    BenchRec H = Bench[LT_HEADER];
    bool valid = (H.role == ROLE_HEADER) && (H.active > 0.5) && (H.kind == (float)PLAN_VERSION);

    uint salt      = valid ? (uint)clamp(H.tone, 0.0, 65535.0) : 3u;
    uint storedSig = valid ? LtSigUnpack(H.p1) : 0u;
    int  sel       = valid ? (int)clamp(H.p0.x, -1.0, (float)LT_TOTAL) : -1;
    int  drag      = valid ? (int)clamp(H.p0.y, -1.0, (float)LT_TOTAL) : -1;
    float2 grab    = valid ? float2(clamp(H.hdg, -4.0, 4.0), clamp(H.r0, -4.0, 4.0)) : float2(0, 0);
    int  dragRot   = valid ? (int)clamp(H.wl1, 0.0, 1.0) : 0;   // 0 = moving, 1 = rotating
    float cmd      = valid ? H.gen : 0.0;

    float apexRr = radians(clamp(prism_apex, 18.0, 86.0));
    uint sig = ltSignature(salt);
    uint nEmit = (uint)clamp((float)emitter_count, 1.0, (float)LT_MAX_EMIT);
    uint nLink = (uint)clamp((float)chain_len, 0.0, (float)(LT_MAX_ELEM - 1));

    // =========================================================================================
    // 1. REGENERATE (signature-driven only) — then commit the signature IMMEDIATELY.
    // =========================================================================================
    if (!valid || storedSig != sig)
    {
        float var = saturate(variation);
        float apexR = apexRr;
        int   famI  = (int)clamp((float)angle_family, 0.0, 4.0);
        float step  = ltAngleStep(famI);
        float phase = ltRnd(salt, 991u) * max(step, 1e-3);

        // ---- emitters ------------------------------------------------------------------------
        // Hand-spawned sources are stepped over, never written through. The generated battery
        // fills whatever slots are left.
        uint eslot = 0u;
        [loop] for (uint ei = 0u; ei < (uint)LT_MAX_EMIT; ++ei)
        {
            while (eslot < (uint)LT_MAX_EMIT &&
                   LtOwnedF(Bench[LT_EMIT_BASE + eslot].flags)) eslot++;
            if (eslot >= (uint)LT_MAX_EMIT) break;
            uint wslot = eslot; eslot++;

            BenchRec E = (BenchRec)0;
            bool live = ei < nEmit;
            E.role = ROLE_EMITTER;
            E.active = live ? 1.0 : 0.0;
            E.kind = (float)clamp((float)beam_profile, 0.0, (float)(BP_COUNT - 1));
            E.tone = (float)clamp((float)beam_spectrum, 0.0, (float)(SP_COUNT - 1));
            E.seed = ltRnd(salt + ei * 37u, 5u) * 512.0;
            E.r0 = 1.0;
            E.r1 = beam_divergence;
            E.wl0 = band_center;
            E.wl1 = band_width;
            E.p1 = float2(beam_aperture, 0.0);
            E.flags = LtSetFlag(0.0, F_ANCHOR, true);
            E.z = 0.0;
            E.gen = (float)clamp((float)beam_shape, 0.0, 1.0);   // 0 flat-top, 1 gaussian TEM00

            // Emitter 0 is the reference beam. Extra emitters fan out around it — a battery of
            // sources aimed at the same first element, which is what makes multiple emitters
            // worth having at all rather than three beams pointing at nothing.
            float2 pos = REF_EMIT_POS;
            float  hdg = REF_EMIT_HDG;
            if (ei > 0u)
            {
                // CLAMPED INTO THE BENCH. The fan-out used to spread +/-0.15 about the reference
                // position, which puts the second source at y = 0.655 on a bench only 0.5625 deep
                // — off the plan, so it could be neither seen nor clicked, and there was no way to
                // delete it. A record nobody can reach is worse than one that is merely misplaced.
                float k = (float)ei / max((float)nEmit - 1.0, 1.0);
                float span = min(0.30, BENCH_H - 0.12);
                pos = float2(REF_EMIT_POS.x + (k - 0.5) * 0.005,
                             REF_EMIT_POS.y + (k - 0.5) * span);
                pos = clamp(pos, float2(0.020, 0.045), float2(0.320, BENCH_H - 0.045));
                hdg = REF_EMIT_HDG + (k - 0.5) * 0.52;
            }
            if (var > 0.0)
            {
                float2 rp = float2(ltRange(salt + ei * 71u, 11u, 0.03, 0.16),
                                   ltRange(salt + ei * 71u, 12u, 0.10, BENCH_H - 0.04));
                float rh = ltRange(salt + ei * 71u, 13u, -1.25, 0.25);
                pos = lerp(pos, rp, var);
                hdg = lerp(hdg, ltSnapAngle(rh, step, phase), var);
            }
            E.p0 = pos; E.hdg = hdg;
            Bench[LT_EMIT_BASE + wslot] = E;
        }

        // ---- the chain -------------------------------------------------------------------------
        // Every element is placed ON THE BEAM leaving the previous one. That single decision is
        // what makes a re-roll produce a bench instead of debris: an element sitting on the ray
        // is lit by construction, and no amount of stratified coordinate drawing achieves that.
        //
        // Hand-spawned elements are allocated AROUND, exactly like the sources: build a bench by
        // hand and it survives every reseed and every variation sweep of the generated part.
        BenchRec E0 = Bench[LT_EMIT_BASE];
        [loop] for (uint fe = 0u; fe < (uint)LT_MAX_EMIT; ++fe)
        {
            BenchRec Ec = Bench[LT_EMIT_BASE + fe];
            if (Ec.active > 0.5) { E0 = Ec; break; }
        }
        float2 cur = E0.p0;
        float  ang = E0.hdg;

        float2 bbMin = cur, bbMax = cur;
        uint gslot = 0u;

        [loop] for (uint li = 0u; li < (uint)LT_MAX_ELEM; ++li)
        {
            while (gslot < (uint)LT_MAX_ELEM &&
                   LtOwnedF(Bench[LT_ELEM_BASE + gslot].flags)) gslot++;
            if (gslot >= (uint)LT_MAX_ELEM) break;
            uint idx = (uint)LT_ELEM_BASE + gslot; gslot++;

            BenchRec R = (BenchRec)0;
            R.role = ROLE_ELEMENT;

            if (li >= nLink) { R.active = 0.0; Bench[idx] = R; continue; }

            uint h = ltHash2(salt + li * 613u, 17u);

            int tKind, tMat; float tSize, tDev, tDist;
            ltTemplateLink((int)layout_preset, li, nLink, salt, tKind, tMat, tSize, tDev, tDist);

            // The last link is always a screen: the fan has to LAND on something or the whole
            // subject fades out mid-air. Guaranteed by construction, not hoped for.
            bool terminal = (li == nLink - 1u) && (nLink > 1u);

            int kind = terminal ? EK_SCREEN : tKind;
            int mat  = tMat;
            float sizeF = tSize;
            float devWant = tDev;
            float dist = tDist;

            if (var > 0.0 && !terminal)
            {
                int rk = ltDrawKind(h, w_prism, w_mirror, w_optic, w_control);
                if (ltRnd(h, 301u) < var) kind = rk;
                if (ltRnd(h, 302u) < var) mat = (int)(ltRnd(h, 303u) * (float)GM_COUNT * 0.999);
                sizeF = lerp(sizeF, ltRange(h, 304u, 0.62, 1.30), var);
                // Draw the DEFLECTION, not a coordinate. Snapped to the angle family so the
                // bench reads as designed; snapped after the blend, because the average of two
                // snapped angles is not snapped.
                float rdev = ltRange(h, 305u, -1.05, 1.05);
                devWant = lerp(devWant, rdev, var);
                dist = lerp(dist, ltRange(h, 306u, 0.16, 0.40), var);
            }

            // Below the touching distance the elements interpenetrate and the chain stops being
            // a chain. Clamp both ways: too far and the beam leaves the bench before arriving.
            dist = clamp(dist * throw_scale, 0.115, 0.62);

            float2 p1v; float r0v, r1v;
            ltDefaultSize(kind, dist, sizeF, apexR, p1v, r0v, r1v);
            if (kind == EK_PRISM) p1v.x = max(prism_size * sizeF, 0.03);

            float2 pos = cur + ltDir(ang) * dist;

            float nd = ltIOR(mat, WL_D);
            float hdg;
            if (kind == EK_PRISM)
            {
                r1v = (devWant >= 0.0) ? 1.0 : -1.0;         // which side the base is on
                hdg = ltPrismMinDevHdg(ang, apexR, nd, r1v);
                // and then sit it ON the beam by its entry face, not by its centroid
                pos = ltPrismCentreOnRay(pos, hdg, p1v.x, apexR, cur, ltDir(ang));
            }
            else
            {
                float dv = devWant;
                if (kind == EK_MIRROR || kind == EK_SPLITTER)
                {
                    // A mirror's deflection IS free, so it is the one that carries the angle
                    // family. Keep it away from grazing, where a mirror stops folding the path
                    // and starts skimming past it.
                    dv = ltSnapAngle(clamp(dv, -2.4, 2.4), step, phase);
                    if (abs(dv) < 0.35) dv = (dv < 0.0 ? -1.0 : 1.0) * max(step, 0.6);
                }
                hdg = ltSolveHdg(kind, ang, dv, apexR, nd);
            }

            R.p0 = pos; R.p1 = p1v; R.hdg = hdg;
            R.kind = (float)kind;
            R.tone = (float)clamp((float)mat, 0.0, (float)(GM_COUNT - 1));
            R.r0 = (kind == EK_PRISM) ? apexR : r0v;
            R.r1 = r1v;
            R.seed = ltRnd(h, 7u) * 512.0;
            R.gen = ltRnd(h, 8u) * 512.0;
            R.par = (float)((li == 0u) ? -1 : (int)(LT_ELEM_BASE + li - 1u));
            R.att = dist;
            R.dev = devWant;
            R.z = (float)li;
            R.active = 1.0;
            R.wl0 = -1.0; R.wl1 = 0.0;
            // Arm the one-shot for prisms: the chain builder already solved this angle, but
            // `dispersion` sits outside the layout signature, so the first resolve after a change
            // re-lands it exactly. It clears itself immediately afterwards.
            if (kind == EK_PRISM) R.flags = LtSetFlag(R.flags, F_AIM, true);
            Bench[idx] = R;

            // Advance along the deviated ray. A prism's deviation is the physics' answer, so it
            // is read back rather than assumed.
            float actualDev;
            if (kind == EK_PRISM)      actualDev = ltMinDeviation(apexR, nd) * r1v;
            else if (kind == EK_MIRROR || kind == EK_SPLITTER)
            {
                float2 nn = ltDir(hdg);
                float2 din = ltDir(ang);
                float2 dout = ltReflect2(din, dot(nn, din) < 0.0 ? nn : -nn);
                actualDev = atan2(din.x * dout.y - din.y * dout.x, dot(din, dout));
            }
            else actualDev = 0.0;

            cur = pos;
            ang = ang + actualDev;

            float ext = max(p1v.x, p1v.y) * 1.25;
            bbMin = min(bbMin, pos - ext); bbMax = max(bbMax, pos + ext);
        }

        // ---- THE FIT PASS ----------------------------------------------------------------------
        // A chain grows in whatever direction its deflections take it, and says nothing about
        // where it ends up or how big it is — the single most common way a random seed looks
        // broken. One UNIFORM similarity transform recentres and zooms it into the bench, so no
        // proportion changes and no element leaves its neighbours.
        if (var > 0.0 && fit_frame > 0.0)
        {
            float2 mar = float2(0.055, 0.045);
            float2 span = max(bbMax - bbMin, 1e-3);
            float2 target = float2(1.0, BENCH_H) - mar * 2.0;
            float k = min(target.x / span.x, target.y / span.y);
            k = clamp(k, 0.25, 3.0);
            k = lerp(1.0, k, saturate(fit_frame) * var);

            float2 c0 = (bbMin + bbMax) * 0.5;
            float2 c1 = float2(0.5, BENCH_H * 0.5);
            c1 = lerp(c0, c1, saturate(fit_frame) * var);

            [loop] for (uint fi = 0u; fi < (uint)(LT_MAX_EMIT + LT_MAX_ELEM); ++fi)
            {
                uint idx = (uint)LT_EMIT_BASE + fi;
                BenchRec R = Bench[idx];
                if (R.active < 0.5) continue;
                if (LtOwnedF(R.flags)) continue;   // hand-placed: the fit does not move it
                R.p0 = (R.p0 - c0) * k + c1;
                if (R.role == ROLE_ELEMENT)
                {
                    R.p1 *= k;
                    if ((int)R.kind == EK_LENS) R.r0 *= k;
                }
                else R.p1.x *= k;
                Bench[idx] = R;
            }
        }

        // COMMIT THE SIGNATURE NOW, before any event can change the salt.
        H = (BenchRec)0;
        H.role = ROLE_HEADER;
        H.kind = (float)PLAN_VERSION;
        H.tone = (float)salt;
        H.p0 = float2(-1.0, -1.0);
        H.p1 = LtSigPack(sig);
        H.active = 1.0;
        H.gen = cmd;
        Bench[LT_HEADER] = H;
        sel = -1; drag = -1; grab = float2(0, 0);
    }

    // =========================================================================================
    // 2. EVENTS. Reduced in order, single-threaded.
    // =========================================================================================
    LtLayout L = ltLayout(_Resolution.xy);

    [loop] for (uint e = 0u; e < min(_ViewportEventCount, 64u); ++e)
    {
        ViewportEvent ev = _ViewportEvents[e];
        float2 px = ev.position * _Resolution.xy;

        bool isClick  = (ev.type == 5u && ev.code == 1u && ev.phase == 7u);
        bool dragBeg  = (ev.type == 5u && ev.code == 3u && ev.phase == 5u);
        bool dragUpd  = (ev.type == 5u && ev.code == 3u && ev.phase == 6u);
        bool dragEnd  = (ev.type == 5u && ev.code == 3u && (ev.phase == 7u || ev.phase == 8u));

        if (isClick || dragBeg)
        {
            // PICK IN THE SAME SPACE WE DRAW IN. Smallest-hit-wins, so a small element resting
            // near a big one stays reachable.
            int hit = -1;
            float best = 1e9;

            if (ltInBox(L.plan, px))
            {
                float2 bp = ltPixToBench(L, px);

                [loop] for (uint i = 0u; i < (uint)LT_MAX_EMIT; ++i)
                {
                    BenchRec R = Bench[LT_EMIT_BASE + i];
                    if (R.active < 0.5) continue;
                    float r = 0.030;
                    if (length(bp - R.p0) < r && r < best) { best = r; hit = (int)(LT_EMIT_BASE + i); }
                }
                [loop] for (uint j = 0u; j < (uint)LT_MAX_ELEM; ++j)
                {
                    BenchRec R = Bench[LT_ELEM_BASE + j];
                    if (R.active < 0.5) continue;
                    int k = (int)R.kind;
                    float d, r;
                    if (k == EK_PRISM || k == EK_SLAB || k == EK_LENS)
                    {
                        r = max(R.p1.x, 0.02) * ((k == EK_PRISM) ? 0.80 : 1.05);
                        d = length(bp - R.p0);
                    }
                    else
                    {
                        // Planar elements are picked against the FACE, not a disc — a 0.9-unit
                        // screen would otherwise swallow every click on the bench.
                        float2 tg = ltPerp(ltDir(R.hdg));
                        float2 rel = bp - R.p0;
                        float u = clamp(dot(rel, tg), -R.p1.x, R.p1.x);
                        d = length(rel - tg * u);
                        r = max(R.p1.y, 0.012) + 0.012;
                    }
                    if (d < r && r < best) { best = r; hit = (int)(LT_ELEM_BASE + j); }
                }
            }

            sel = hit;
            if (dragBeg && hit >= 0)
            {
                drag = hit;
                grab = Bench[hit].p0 - ltPixToBench(L, px);
                // Decided ONCE, here, and remembered for the whole gesture.
                dragRot = (ViewportButtonDown(1u) ||
                           (ev.modifiers & VIEWPORT_MODIFIER_SHIFT) != 0u) ? 1 : 0;
            }
        }
        else if (dragUpd && drag >= 0)
        {
            BenchRec R = Bench[drag];
            if (ltInBox(L.plan, px))
            {
                float2 bp = ltPixToBench(L, px);
                if (dragRot != 0)
                {
                    // Rotate: the heading points from the element at the cursor. A prism rotated
                    // by hand stops auto-solving — the user's angle wins from then on.
                    float2 v = bp - R.p0;
                    if (length(v) > 1e-4)
                    {
                        R.hdg = atan2(v.y, v.x);
                        R.flags = LtSetFlag(R.flags, F_AIM, false);   // your angle wins
                        R.flags = LtSetFlag(R.flags, F_MANUAL, true);
                        R.flags = LtSetFlag(R.flags, F_EDITED, true);
                    }
                }
                else
                {
                    R.p0 = clamp(bp + grab, float2(-0.05, -0.05), float2(1.05, BENCH_H + 0.05));
                    R.flags = LtSetFlag(R.flags, F_EDITED, true);
                }
                Bench[drag] = R;
                cmd += 1.0;
            }
        }
        else if (dragEnd)
        {
            drag = -1; dragRot = 0;
        }
        else if (ev.type == 3u)     // wheel — resize the selection
        {
            if (sel >= 0)
            {
                BenchRec R = Bench[sel];
                float f = (ev.value > 0.0) ? 1.10 : (1.0 / 1.10);
                if (R.role == ROLE_ELEMENT)
                {
                    R.p1 = clamp(R.p1 * f, 0.006, 1.20);
                    if ((int)R.kind == EK_LENS) R.r0 = clamp(R.r0 * f, 0.02, 2.0);
                }
                else R.p1.x = clamp(R.p1.x * f, 0.002, 0.20);
                R.flags = LtSetFlag(R.flags, F_EDITED, true);
                Bench[sel] = R;
                cmd += 1.0;
            }
        }
        else if (ev.type == 4u && ev.phase == 1u)
        {
            // A KEY CARRYING CTRL / ALT / CMD IS THE HOST'S, NOT THE BENCH'S.
            //
            // Without this the module sees Ctrl+Z as a bare Z and wipes the bench when the user
            // meant to undo. The same trap was armed on Ctrl+S, Ctrl+A and Ctrl+D — save, select
            // all and a common delete — which are add-source, add-element and delete here. Any
            // authored binding on a bare letter has this problem; the guard belongs at the top of
            // the handler rather than on each key.
            if ((ev.modifiers & (VIEWPORT_MODIFIER_CONTROL |
                                 VIEWPORT_MODIFIER_ALT |
                                 VIEWPORT_MODIFIER_SUPER)) != 0u) continue;

            uint kc = ev.code;
            uint nonce = ltHash2(ev.sequence + 1u, (uint)(_Time * 1000.0));

            // ---- SPAWN AND DELETE ------------------------------------------------------------
            // The bench is meant to be BUILT, not just re-rolled. A spawned record is marked
            // F_USER, which is the one thing the generator refuses to write over — so a bench
            // assembled by hand survives every reseed, preset change and variation sweep.
            // Spawn at the cursor, or at the middle of the bench if the pointer is not over the
            // plan. A key that silently does nothing is indistinguishable from a broken key.
            float2 pxPtr = _ViewportPointerPosition * _Resolution.xy;
            float2 cursor = ltInBox(L.plan, pxPtr) ? ltPixToBench(L, pxPtr)
                                                   : float2(0.5, BENCH_H * 0.5);
            cursor = clamp(cursor, float2(0.02, 0.02), float2(0.98, BENCH_H - 0.02));

            // A new element aims at the nearest live source, so a dropped mirror or screen faces
            // the light instead of pointing at an arbitrary zero.
            float2 toward = float2(1.0, 0.0);
            float bestD = 1e9;
            [loop] for (uint ni = 0u; ni < (uint)LT_MAX_EMIT; ++ni)
            {
                BenchRec Es = Bench[LT_EMIT_BASE + ni];
                if (Es.role != ROLE_EMITTER || Es.active < 0.5) continue;
                float dd = length(Es.p0 - cursor);
                if (dd < bestD && dd > 1e-4) { bestD = dd; toward = normalize(Es.p0 - cursor); }
            }
            float faceHdg = atan2(toward.y, toward.x);

            if (kc == 1u)                                    // A — add an optical element
            {
                int slot = -1;
                [loop] for (uint ai = 0u; ai < (uint)LT_MAX_ELEM; ++ai)
                    if (Bench[LT_ELEM_BASE + ai].active < 0.5) { slot = (int)(LT_ELEM_BASE + ai); break; }
                if (slot >= 0)
                {
                    // Inherit from the selection when there is one, so "another of these" is one
                    // keystroke rather than a spawn plus five cycles.
                    BenchRec S = (BenchRec)0;
                    if (sel >= LT_ELEM_BASE) S = Bench[sel];
                    bool inherit = (sel >= LT_ELEM_BASE) && (S.role == ROLE_ELEMENT) && (S.active > 0.5);

                    int nk = inherit ? (int)S.kind : EK_PRISM;
                    float2 np1; float nr0, nr1;
                    ltDefaultSize(nk, 0.30, 1.0, apexRr, np1, nr0, nr1);

                    BenchRec N = (BenchRec)0;
                    N.role = ROLE_ELEMENT;
                    N.active = 1.0;
                    N.kind = (float)nk;
                    N.tone = inherit ? S.tone : (float)clamp((float)glass_material, 0.0, (float)(GM_COUNT - 1));
                    N.p0 = cursor;
                    N.p1 = inherit ? S.p1 : np1;
                    N.r0 = inherit ? S.r0 : ((nk == EK_PRISM) ? apexRr : nr0);
                    N.r1 = inherit ? S.r1 : nr1;
                    N.hdg = inherit ? S.hdg : faceHdg;
                    N.seed = (float)(ltHashU(nonce) % 512u);
                    N.gen = (float)(ltHashU(nonce + 3u) % 512u);
                    N.par = -1.0; N.att = 0.30; N.dev = 0.0; N.z = 0.0;
                    N.wl0 = -1.0; N.wl1 = 0.0;
                    // USER and EDITED so the generator never writes over it, plus a ONE-SHOT AIM:
                    // a prism dropped on a beam snaps to minimum deviation on the very next cook
                    // and then holds that angle for good. Helpful once, never surprising after.
                    N.flags = LtSetFlag(LtSetFlag(0.0, F_USER, true), F_EDITED, true);
                    if (nk == EK_PRISM) N.flags = LtSetFlag(N.flags, F_AIM, true);
                    Bench[slot] = N;
                    sel = slot;
                }
            }
            else if (kc == 19u)                              // S — add a source
            {
                int slot = -1;
                [loop] for (uint si = 0u; si < (uint)LT_MAX_EMIT; ++si)
                    if (Bench[LT_EMIT_BASE + si].active < 0.5) { slot = (int)(LT_EMIT_BASE + si); break; }
                if (slot >= 0)
                {
                    BenchRec N = (BenchRec)0;
                    N.role = ROLE_EMITTER;
                    N.active = 1.0;
                    N.kind = (float)clamp((float)beam_profile, 0.0, (float)(BP_COUNT - 1));
                    N.tone = (float)clamp((float)beam_spectrum, 0.0, (float)(SP_COUNT - 1));
                    N.p0 = cursor;
                    N.p1 = float2(beam_aperture, 0.0);
                    N.r0 = 1.0; N.r1 = beam_divergence;
                    N.wl0 = band_center; N.wl1 = band_width;
                    N.seed = (float)(ltHashU(nonce + 5u) % 512u);
                    N.gen = (float)clamp((float)beam_shape, 0.0, 1.0);
                    // Aimed at the selected element if there is one, otherwise at the middle of
                    // the bench. A new source that points at nothing is a new source nobody wants.
                    float2 aim = float2(0.5, BENCH_H * 0.5);
                    if (sel >= LT_ELEM_BASE && Bench[sel].active > 0.5) aim = Bench[sel].p0;
                    float2 v = aim - cursor;
                    N.hdg = (length(v) > 1e-4) ? atan2(v.y, v.x) : 0.0;
                    N.flags = LtSetFlag(LtSetFlag(LtSetFlag(0.0, F_USER, true), F_EDITED, true),
                                        F_ANCHOR, true);
                    Bench[slot] = N;
                    sel = slot;
                }
            }
            // D, not Backspace. The host router gives text-editing keys priority over authored
            // bindings, so Backspace is consumed upstream and the event never reaches the module —
            // which presents as a dead key with nothing in the logs to explain it.
            else if (kc == 4u && sel >= 0)                   // D — delete the selection
            {
                BenchRec R = Bench[sel];
                R.active = 0.0;
                R.flags = 0.0;                                // release the slot back to the pool
                Bench[sel] = R;
                sel = -1; drag = -1;
            }
            else if (kc == 32u)                              // 0 — clear the whole bench
            {
                // EVERYTHING. Sources, elements, generated and hand-built alike, and the flags
                // with them so nothing stays reserved. The salt is deliberately NOT bumped: the
                // signature is unchanged, so the generator does not immediately refill and you are
                // left with a genuinely empty bench to build on. R re-rolls a generated one back.
                [loop] for (uint zi = 0u; zi < (uint)(LT_MAX_EMIT + LT_MAX_ELEM); ++zi)
                {
                    uint zidx = (uint)LT_EMIT_BASE + zi;
                    BenchRec R = Bench[zidx];
                    R.active = 0.0;
                    R.flags = 0.0;
                    Bench[zidx] = R;
                }
                sel = -1; drag = -1;
            }
            else if (kc == 3u) sel = -1;                                                // C
            else if (kc == 18u) { salt = (salt * 1103515245u + 12345u) & 0xFFFFu; }     // R
            else if (sel >= 0)
            {
                BenchRec R = Bench[sel];
                bool isElem = (R.role == ROLE_ELEMENT);

                if (kc == 11u)                                    // K — cycle kind / spectrum
                {
                    if (isElem)
                    {
                        int nk = ((int)R.kind + 1) % EK_COUNT;
                        float2 np1; float nr0, nr1;
                        ltDefaultSize(nk, max(R.att, 0.25), 1.0, radians(clamp(prism_apex, 18.0, 86.0)), np1, nr0, nr1);
                        // Preserve the FOOTPRINT across a kind change, so cycling an element does
                        // not also resize the composition.
                        float keep = max(R.p1.x, 1e-4) / max(np1.x, 1e-4);
                        R.p1 = np1 * keep; R.r0 = (nk == EK_PRISM) ? radians(clamp(prism_apex, 18.0, 86.0)) : nr0;
                        R.r1 = nr1;
                        R.kind = (float)nk;
                    }
                    else R.tone = (float)(((int)R.tone + 1) % SP_COUNT);
                    R.flags = LtSetFlag(R.flags, F_EDITED, true);
                }
                else if (kc == 13u)                               // M — cycle material / profile
                {
                    if (isElem) R.tone = (float)(((int)R.tone + 1) % GM_COUNT);
                    else        R.kind = (float)(((int)R.kind + 1) % BP_COUNT);
                    R.flags = LtSetFlag(R.flags, F_EDITED, true);
                }
                else if (kc == 24u)                               // X — on / off
                {
                    R.flags = LtSetFlag(R.flags, F_OFF, !LtFlagF(R.flags, F_OFF));
                }
                else if (kc == 16u)                               // P — re-aim to minimum deviation
                {
                    R.flags = LtSetFlag(R.flags, F_AIM, true);    // fires once, next cook
                    R.flags = LtSetFlag(R.flags, F_MANUAL, false);
                    R.r1 = -R.r1;                                 // and flip which way it bends
                }
                else if (kc == 14u)                               // N — re-roll this record
                {
                    R.seed = (float)(ltHashU(nonce) % 512u);
                    R.gen  = (float)(ltHashU(nonce + 7u) % 512u);
                    if (isElem)
                    {
                        R.tone = (float)(ltHashU(nonce + 11u) % (uint)GM_COUNT);
                        if ((int)R.kind == EK_PRISM) R.r0 = radians(ltRange(nonce, 21u, 28.0, 74.0));
                    }
                    R.flags = LtSetFlag(R.flags, F_EDITED, true);
                }
                else if (kc == 7u || kc == 8u)                    // G / H — grow / shrink
                {
                    float f = (kc == 7u) ? 1.12 : (1.0 / 1.12);
                    if (isElem)
                    {
                        R.p1 = clamp(R.p1 * f, 0.006, 1.20);
                        if ((int)R.kind == EK_LENS) R.r0 = clamp(R.r0 * f, 0.02, 2.0);
                    }
                    else R.p1.x = clamp(R.p1.x * f, 0.002, 0.20);
                    R.flags = LtSetFlag(R.flags, F_EDITED, true);
                }
                Bench[sel] = R;
                cmd += 1.0;
            }
        }
    }

    // =========================================================================================
    // 3. RESOLVE. Walk the chief ray at the d-line, re-solving every AUTO prism from the ray
    //    that actually arrives, and record what light reached what.
    //
    //    This is what makes the bench feel alive: drag the emitter and every prism downstream
    //    re-aims itself to minimum deviation, because its orientation is DERIVED from the beam
    //    rather than stored as an independent number that has to be kept in agreement by hand.
    // =========================================================================================
    // REACHABILITY INVARIANT. Anything live is pulled back inside the drawn bench before it can
    // be orphaned. Picking is gated on the plan rectangle and drawing is clipped to it, so a
    // record outside is simultaneously invisible and unselectable — there is no gesture that can
    // recover it. This is a bounds guard, not a placement decision: it is a no-op for every record
    // already on the bench, and it only ever moves one that has escaped.
    [loop] for (uint bi = 0u; bi < (uint)(LT_MAX_EMIT + LT_MAX_ELEM); ++bi)
    {
        uint bidx = (uint)LT_EMIT_BASE + bi;
        BenchRec R = Bench[bidx];
        if (R.active < 0.5) continue;
        float2 cp = clamp(R.p0, float2(0.012, 0.012), float2(0.988, BENCH_H - 0.012));
        if (any(abs(cp - R.p0) > 1e-6)) { R.p0 = cp; Bench[bidx] = R; }
    }

    [loop] for (uint ci = 0u; ci < (uint)LT_MAX_ELEM; ++ci)
    {
        BenchRec R = Bench[LT_ELEM_BASE + ci];
        if (R.role != ROLE_ELEMENT) continue;
        R.flags = LtSetFlag(R.flags, F_UNLIT, true);
        R.flags = LtSetFlag(R.flags, F_ALARM, false);
        R.wl0 = -1.0; R.wl1 = 0.0;
        Bench[LT_ELEM_BASE + ci] = R;
    }

    int   alarms = 0;
    int   litCount = 0;
    float chiefDev = 0.0;

    // ONE SOURCE OWNS AN AUTO PRISM PER COOK — the first one whose beam reaches it, in emitter
    // index order. The resolve walk below runs once per source, so without this a prism lit by two
    // sources is re-solved twice every cook and ends up aimed by whichever emitter happened to be
    // processed last. Adding a second source would then visibly wrench the first prism around.
    // 64 bits, one per element slot.
    uint solvedA = 0u, solvedB = 0u;

    [loop] for (uint em = 0u; em < (uint)LT_MAX_EMIT; ++em)
    {
        BenchRec E = Bench[LT_EMIT_BASE + em];
        if (E.active < 0.5 || LtFlagF(E.flags, F_OFF)) continue;

        float2 o = E.p0;
        float2 d = ltDir(E.hdg);
        int inside = -1;
        float dev = 0.0;
        float travelled = 0.0;

        [loop] for (uint it = 0u; it < (uint)CHIEF_MAX; ++it)
        {
            LtScene h = ltTraceScene(o, d, inside, -1);
            if (h.elem < 0) break;

            // Re-aim an AUTO prism from the ray that is actually about to arrive, then re-query so
            // the rest of the walk sees the orientation it will really have.
            //
            // ANGLE ONLY. This used to re-centre the prism onto the beam as well, which was a nice
            // trick with one source and wrong in every other case: POSITION IS A RECORD THE USER
            // OWNS, and a resolve pass silently rewriting it every cook means an element jumps when
            // you move something else entirely. Placement is decided once, when the chain is built
            // or when you drop the prism; only the angle is derived from the physics thereafter.
            if (inside < 0 && h.kind == EK_PRISM)
            {
                uint ebit = (uint)max(h.elem - LT_ELEM_BASE, 0);
                bool claimed = (ebit < 32u) ? (((solvedA >> ebit) & 1u) != 0u)
                                            : (((solvedB >> (ebit - 32u)) & 1u) != 0u);
                BenchRec P = Bench[h.elem];
                if (!claimed && LtFlagF(P.flags, F_AIM))
                {
                    if (ebit < 32u) solvedA |= (1u << ebit);
                    else            solvedB |= (1u << (ebit - 32u));

                    float ndd = ltIOR((int)clamp(P.tone, 0.0, (float)(GM_COUNT - 1)), WL_D);
                    float side = (P.r1 >= 0.0) ? 1.0 : -1.0;
                    P.hdg = ltPrismMinDevHdg(atan2(d.y, d.x), P.r0, ndd, side);
                    P.flags = LtSetFlag(P.flags, F_AIM, false);   // ONE SHOT. Never again.
                    Bench[h.elem] = P;
                    h = ltTraceScene(o, d, inside, -1);
                    if (h.elem < 0) break;
                }
            }

            BenchRec R = Bench[h.elem];
            travelled += h.t;

            if (LtFlagF(R.flags, F_UNLIT))
            {
                R.flags = LtSetFlag(R.flags, F_UNLIT, false);
                R.wl0 = travelled;
                R.wl1 = acos(saturate(-dot(d, h.n)));    // incidence angle at first contact
                litCount++;
            }

            float2 nd2 = d;
            bool stop = false;
            int k = h.kind;

            if (k == EK_SCREEN || k == EK_BLOCK) { stop = true; }
            else if (k == EK_MIRROR)   { nd2 = ltReflect2(d, h.n); }
            else if (k == EK_SPLITTER) { nd2 = d; }
            else
            {
                int mat = (int)clamp(R.tone, 0.0, (float)(GM_COUNT - 1));
                float ng = ltIOR(mat, WL_D);
                bool entering = h.entering;
                float2 refr;
                bool ok = ltRefract2(d, h.n, entering ? 1.0 : ng, entering ? ng : 1.0, refr);
                if (!ok)
                {
                    // TIR on the way OUT means this element swallowed the spectrum. Physically
                    // correct, creatively almost always wrong, and invisible in a plan view
                    // unless the diagram says so.
                    if (!entering)
                    {
                        R.flags = LtSetFlag(R.flags, F_ALARM, true);
                        alarms++;
                    }
                    nd2 = ltReflect2(d, h.n);
                }
                else
                {
                    nd2 = refr;
                    inside = entering ? h.elem : -1;
                }
            }

            Bench[h.elem] = R;

            float cz = d.x * nd2.y - d.y * nd2.x;
            dev += atan2(cz, clamp(dot(d, nd2), -1.0, 1.0));

            if (stop) break;
            o = h.t * d + o + nd2 * 2.0e-4;
            d = nd2;
        }
        if (em == 0u) chiefDev = dev;
    }

    // Elements that no light reached, and the one condition that means the whole bench is dark.
    [loop] for (uint ui = 0u; ui < (uint)LT_MAX_ELEM; ++ui)
    {
        BenchRec R = Bench[LT_ELEM_BASE + ui];
        if (R.role != ROLE_ELEMENT || R.active < 0.5 || LtFlagF(R.flags, F_OFF)) continue;
        if (LtFlagF(R.flags, F_UNLIT)) alarms++;
    }

    // =========================================================================================
    // 4. HEADER WRITEBACK. Never the signature here — see the file header.
    // =========================================================================================
    uint liveElem = 0u, liveEmit = 0u;
    [loop] for (uint qi = 0u; qi < (uint)LT_MAX_ELEM; ++qi)
        if (Bench[LT_ELEM_BASE + qi].active > 0.5) liveElem++;
    [loop] for (uint qj = 0u; qj < (uint)LT_MAX_EMIT; ++qj)
        if (Bench[LT_EMIT_BASE + qj].active > 0.5) liveEmit++;

    H = Bench[LT_HEADER];
    H.role = ROLE_HEADER;
    H.kind = (float)PLAN_VERSION;
    H.tone = (float)salt;
    H.active = 1.0;
    H.p0 = float2((float)sel, (float)drag);
    H.p1 = LtSigPack(sig);
    H.hdg = grab.x; H.r0 = grab.y;
    H.seed = (float)(liveElem + liveEmit);
    H.r1 = (float)liveElem;
    H.att = (float)liveEmit;
    H.dev = clamp((float)rail_target, 0.0, (float)(LT_MAX_EMIT - 1));
    H.z = (float)alarms;
    H.gen = cmd;
    H.par = dispersion;          // downstream nodes read the gain from here, never their own copy
    H.wl0 = degrees(chiefDev);
    H.wl1 = (float)dragRot;      // the live gesture's mode, latched at drag-begin
    Bench[LT_HEADER] = H;
}
