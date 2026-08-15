// paths.hlsli — the LT_Trace -> LT_Field data contract, AND the trace kernel itself.
//
// The kernel lives here rather than in either node because BOTH the plan's spectral rail and the
// renderer's fan must be the same physics. If the diagram reconstructed the path with its own
// maths, the two would eventually disagree, and the disagreement would present as a physics bug
// in a picture instead of as a mismatch between two files.
//
// SM 5.0 cannot pass resources as function arguments, so the two buffers are addressed through
// LT_BENCH and LT_PATHS macros that the consuming shader points at its own declarations.
#ifndef SPECTRAL_PATHS_HLSLI
#define SPECTRAL_PATHS_HLSLI

#include "../_shared/optics.hlsli"

// The kernel exists only for a consumer that declared BOTH buffers and pointed the macros at
// them. `PathSeg`, the lane budget and the record contract live in bench.hlsli precisely so that
// a consumer can declare its buffers BEFORE reaching this file.
#if defined(LT_BENCH) && defined(LT_PATHS)

void ltWriteSeg(uint slot, float2 a, float2 b, float wl, float power,
                int evt, int evtEnd, float lane, uint depth, int elem, float dev, float ior)
{
    PathSeg s;
    s.a = a; s.b = b;
    s.wl = wl; s.power = power;
    s.evt = (float)evt; s.evtEnd = (float)evtEnd;
    s.lane = lane; s.depth = (float)depth;
    s.elem = (float)elem; s.dev = dev; s.ior = ior;
    LT_PATHS[slot] = s;
}

void ltWriteDead(uint slot)
{
    PathSeg s = (PathSeg)0;
    s.power = 0.0; s.elem = -1.0; s.evt = (float)EV_EMIT; s.evtEnd = (float)EV_EMIT;
    LT_PATHS[slot] = s;
}

// ---------------------------------------------------------------------------------------------
// THE KERNEL.
//
// `branch` selects which reflection this lane follows, and it is the whole reason the reference
// image has three families of light in it rather than one:
//   0  always take the transmitted route. The fan.
//   1  take the reflection at the FIRST dielectric interface. That is the white, undispersed
//      specular beam leaving the entry face — the one heading upper-right in the photograph.
//   2  take the reflection at the SECOND. That is the ray that failed to leave the exit face,
//      travelled back inside the glass and came out somewhere else — the weak secondary fan.
// Anything beyond that is below the noise floor and is not worth a lane.
// ---------------------------------------------------------------------------------------------
struct LtLane
{
    float wl;
    float power0;
    float lane;
    int   branch;
    uint  maxSeg;
    uint  outBase;
};

uint ltTracePath(float2 ro, float2 rd, LtLane C)
{
    float2 o = ro;
    float2 d = normalize(rd);
    float2 d0 = d;

    int   inside   = -1;      // element index we are travelling inside, -1 = air
    float pw       = C.power0;
    float dev      = 0.0;
    int   curEvt   = EV_EMIT;
    float curIor   = 1.0;
    int   dielSeen = 0;       // dielectric/splitter interfaces met so far
    uint  written  = 0u;
    bool  finished = false;
    bool  tookBranch = (C.branch == 0);   // a branch lane that never branched is a duplicate

    uint budget = min(C.maxSeg, (uint)LT_MAX_SEG);

    [loop] for (uint i = 0u; i < budget; ++i)
    {
        LtScene h = ltTraceScene(o, d, inside, -1);

        if (h.elem < 0)
        {
            float tb = ltBoundExit(o, d);
            ltWriteSeg(C.outBase + written, o, o + d * tb, C.wl, pw,
                       curEvt, EV_ESCAPE, C.lane, i, -1, dev, curIor);
            written++; finished = true;
            break;
        }

        float2 end = o + d * h.t;
        BenchRec e = LT_BENCH[h.elem];
        int k = h.kind;

        int    endEvt  = EV_ESCAPE;
        float2 nd      = d;
        float  npw     = pw;
        int    nInside = inside;
        float  nIor    = curIor;
        bool   terminal = false;

        if (k == EK_SCREEN)
        {
            endEvt = EV_SCREEN; terminal = true;
        }
        else if (k == EK_BLOCK)
        {
            endEvt = EV_ABSORB; terminal = true;
        }
        else if (k == EK_MIRROR)
        {
            nd = ltReflect2(d, h.n);
            npw = pw * saturate(e.r0);
            endEvt = EV_MIRROR;
        }
        else if (k == EK_SPLITTER)
        {
            float R = saturate(e.r0);
            bool takeRefl = (C.branch > 0 && dielSeen == C.branch - 1);
            dielSeen++;
            if (takeRefl) { nd = ltReflect2(d, h.n); npw = pw * R;         endEvt = EV_FRESNEL;
                            tookBranch = true; }
            else          { nd = d;                  npw = pw * (1.0 - R); endEvt = EV_ENTER;   }
        }
        else   // dielectric body
        {
            int   mat = (int)clamp(e.tone, 0.0, (float)(GM_COUNT - 1));
            float ng  = ltIOR(mat, C.wl);
            bool  entering = h.entering;
            float n1 = entering ? 1.0 : ng;
            float n2 = entering ? ng  : 1.0;

            float ci = -dot(d, h.n);
            float R  = ltFresnel(ci, n1, n2);
            float2 refr;
            bool ok = ltRefract2(d, h.n, n1, n2, refr);

            bool takeRefl = (C.branch > 0 && dielSeen == C.branch - 1);
            dielSeen++;

            if (!ok)
            {
                // Total internal reflection. The ray stays in the glass and the exit face has
                // become a mirror — physically correct, and usually NOT what a bench wants,
                // which is why the plan draws it as an alarm.
                nd = ltReflect2(d, h.n); npw = pw; endEvt = EV_TIR;
            }
            else if (takeRefl)
            {
                nd = ltReflect2(d, h.n);
                npw = pw * max(R, 0.015);
                endEvt = EV_FRESNEL;
                tookBranch = true;
            }
            else
            {
                nd  = refr;
                npw = pw * (1.0 - R);
                endEvt  = entering ? EV_ENTER : EV_EXIT;
                nInside = entering ? h.elem : -1;
                nIor    = entering ? ng : 1.0;
            }
        }

        // Signed deviation, accumulated from the emitted heading. This is the number the whole
        // instrument exists to report: the angle between two wavelengths after the last exit IS
        // the dispersion.
        float crossz = d.x * nd.y - d.y * nd.x;
        dev += atan2(crossz, clamp(dot(d, nd), -1.0, 1.0));

        ltWriteSeg(C.outBase + written, o, end, C.wl, pw,
                   curEvt, endEvt, C.lane, i, h.elem, dev, curIor);
        written++;

        if (terminal) { finished = true; break; }
        if (npw < 0.0015) { finished = true; break; }   // below anything anyone can see

        o = end + nd * 2.0e-4;   // push off the surface we just left
        d = nd; pw = npw; inside = nInside; curIor = nIor; curEvt = endEvt;
    }

    // Ran out of budget mid-flight. Say so on the last segment rather than letting the path just
    // stop, because a beam that stops for no reason in the middle of the frame is the single
    // most confusing thing this system can draw.
    if (!finished && written > 0u)
    {
        PathSeg last = LT_PATHS[C.outBase + written - 1u];
        last.evtEnd = (float)EV_EXHAUST;
        LT_PATHS[C.outBase + written - 1u] = last;
    }

    // A branch lane that never found its reflection has retraced the primary exactly. Drawing it
    // would double that beam's brightness for no physical reason, so the lane is discarded.
    if (!tookBranch) written = 0u;

    // Dead-fill to the LANE STRIDE, not to LT_MAX_SEG: the stride is C.maxSeg, and filling past
    // it writes into the next lane's records.
    [loop] for (uint j = written; j < C.maxSeg; ++j) ltWriteDead(C.outBase + j);
    return written;
}

#endif  // LT_BENCH && LT_PATHS

// ---------------------------------------------------------------------------------------------
// Emitter ray geometry. Ray `r` of `n` across the aperture, for a given beam profile.
// ---------------------------------------------------------------------------------------------
// `weight` is this ray's share of the source's power. A real beam is not uniform across its
// aperture — a laser is very nearly gaussian — and a flat-topped bundle is the single thing that
// most makes a rendered beam look like a drawn rectangle instead of light. TEM00 falls off as
// exp(-2 r^2 / w^2); the constant restores the total so switching profile changes the SHAPE of
// the beam and not how much light is on the bench.
void ltEmitRay(BenchRec E, uint r, uint n, out float2 ro, out float2 rd, out float weight)
{
    float t = (n <= 1u) ? 0.0 : (((float)r / (float)(n - 1u)) * 2.0 - 1.0);   // -1..1

    weight = 1.0;
    if (E.gen > 0.5) weight = exp(-2.0 * t * t) * 1.672;
    float ap = max(E.p1.x, 1e-4);
    float2 fwd = ltDir(E.hdg);
    float2 side = ltPerp(fwd);

    int profile = (int)E.kind;
    ro = E.p0 + side * (t * ap * 0.5);
    rd = fwd;

    if (profile == BP_FAN)
    {
        // A fan pivots about the emitter mouth: rays share an origin and spread in angle.
        ro = E.p0;
        rd = ltDir(E.hdg + t * E.r1);
    }
    else if (profile == BP_CONVERGE)
    {
        // Converging on a waist one aperture-length ahead, then diverging past it. Aiming the
        // rays AT a point rather than tilting them keeps the waist where it is claimed to be.
        float2 waist = E.p0 + fwd * max(E.r1, 1e-3);
        rd = normalize(waist - ro);
    }
}

#endif
