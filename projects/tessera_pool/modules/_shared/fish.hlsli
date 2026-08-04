// fish.hlsli — the shared contract for the school.
//
// Same division of labour as tessera.hlsli: nothing here DECIDES anything. TP_School decides
// where the fish are and where they are pointing; this file only says how that is spelled, and
// what shape stands at the answer. TP_Render includes it so the thing it marches is the same
// object TP_School previews, by construction rather than by agreement.
//
// FISH SPACE
//   +x  forward, nose at +len/2, tail at -len/2
//   +y  up (dorsal)
//   +z  right (the axis the body sweeps through when it swims)
//
// Everything is authored in units of BODY LENGTH and scaled at the end. A uniform scale is exact
// for a distance field, so one profile serves every size in the school and there is no second
// set of numbers to keep in step.
#ifndef TP_FISH_HLSLI
#define TP_FISH_HLSLI

// Resolved relative to the SHADER doing the including, not to this file — so this is the path
// from a module folder, and it is correct from TP_School and TP_Render alike because both sit
// one level under modules/.
#include "../_shared/tessera.hlsli"

// ---------------------------------------------------------------------------
// The record. 16 floats / 64 bytes, tightly packed — structured buffers use natural alignment,
// not the 16-byte cbuffer rules, which is why a float3 may sit at offset 12 here.
// ---------------------------------------------------------------------------
struct TpFish
{
    float3 pos;      //  0  tank space
    float3 dir;      // 12  unit heading
    float  phase;    // 24  tail beat phase, radians, integrated not derived from _Time
    float  len;      // 28  body length, world units
    float3 tint;     // 32  the crimson of this individual's markings
    float  speed;    // 44  world units per second
    float  bank;     // 48  roll from turning, radians
    float  seed;     // 52
    float  active;   // 56
    // The authored tail amplitude, carried on the record rather than duplicated as a parameter
    // on the renderer. TP_School owns the swimming; a second copy of this number on TP_Render
    // would be a second place for the shape to disagree with the node that decides it.
    float  sweep;    // 60
};

// SIXTEEN, NOT THIRTY-TWO, AND IT IS A COMPILE-TIME DECISION.
//
// This bound is the trip count of every loop that touches a fish, and the koi field is a large
// function that gets INLINED at each of those sites — once in the primary march, four times in
// the tetrahedral normal, once per shadow march. Doubling the bound doubles the work the shader
// compiler has to do over all of them, and at 32 the march pass went from compiling in seconds
// to compiling in minutes, which makes every hot reload unusable regardless of how it runs.
//
// Sixteen koi in a tank this size is already a crowd. Raise it only with a compile timing in
// hand, never on the assumption that a bigger cap is free.
#define TP_FISH_MAX 16u

// ---------------------------------------------------------------------------
// KOI. Everything below is proportioned to one, and the proportions ARE the job — a koi is not
// a generic fish with different paint on it.
//
//   DEEP-BODIED and strongly laterally compressed: tall through the belly, narrow across.
//   BLUNT ROUNDED HEAD, not a point. There is no taper to speak of forward of the shoulders.
//   FULLEST about a third back from the nose, then a long even run to a narrow peduncle.
//   LARGE SOFT FINS that trail rather than flick — and the paired pectorals especially, which
//   are what make one read as a koi from directly above, and are the thing most often left out.
// ---------------------------------------------------------------------------
float tpKoiProfile(float s)
{
    s = saturate(s);
    // The inner exponent slides the fullest station forward; the outer one sets how BLUNT the
    // two ends are — lower is blunter, and a koi's head is very blunt indeed.
    return pow(sin(3.14159265 * pow(s, 1.45)), 0.52);
}

// How much of the swimming wave this station carries. The head barely moves — a koi holds its
// eyes steady and drives from the back third — so this is deliberately not linear.
float tpFishSweep(float s)
{
    float tailward = saturate(1.0 - s);
    return tailward * tailward * (0.22 + 0.78 * tailward);
}

float2 tpRot2(float2 v, float a)
{
    float c = cos(a), sn = sin(a);
    return float2(v.x * c - v.y * sn, v.x * sn + v.y * c);
}

// A fin: a rounded plate in one plane given a real thickness in the third. This is the standard
// extrude, so it stays a TRUE distance field — the alternative, scaling one axis of the sample
// point, overstates distance along that axis and would need the march slowed down again to
// survive it.
float tpVaneXY(float3 q, float2 hxy, float rad, float halfZ)
{
    float2 d2 = abs(q.xy) - hxy;
    float inPlane = length(max(d2, 0.0)) + min(max(d2.x, d2.y), 0.0) - rad;
    float2 w = float2(inPlane, abs(q.z) - halfZ);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

float tpVaneXZ(float3 q, float2 hxz, float rad, float halfY)
{
    float2 d2 = abs(q.xz) - hxz;
    float inPlane = length(max(d2, 0.0)) + min(max(d2.x, d2.y), 0.0) - rad;
    float2 w = float2(inPlane, abs(q.y) - halfY);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

// ---------------------------------------------------------------------------
// The distance field, in fish space, for a body of unit length.
//
// NOT A TRUE LIPSCHITZ FIELD: the swimming wave bends the domain, and a domain bend inflates
// distances along the bend, so the march that consumes this must take a fraction of each
// reported step (TP_FISH_STEP) or it will punch holes through the fish wherever the tail is
// hard over.
// ---------------------------------------------------------------------------
#define TP_FISH_STEP 0.55

float tpFishUnitSDF(float3 p, float beat, float amp)
{
    float s = saturate(p.x + 0.5);                 // 0 at the tail root, 1 at the nose
    float wav = sin(beat - (1.0 - s) * 4.6) * amp * tpFishSweep(s);

    // ---- body -------------------------------------------------------------------------
    // DIVIDE BY CONSTANTS, NEVER BY THE PROFILE.
    //
    // The first version normalised the cross-section by the profile radius itself, and that
    // radius goes to ZERO at the nose and at the tail. The distance estimate therefore exploded
    // at both ends and the march stalled on a shell around each — one disc in front of the fish
    // and one behind it. The radius belongs on the right of the subtraction, where a zero is
    // just a point instead of a division.
    const float HY = 0.150;                        // half height at the fullest station
    const float HZ = 0.086;                        // half width — koi are narrow across

    float r = tpKoiProfile(s);
    // Rounder below than above: a koi carries its depth in the belly, and a symmetric section
    // reads as a submarine.
    float yScale = (p.y > 0.0) ? HY * 0.90 : HY * 1.10;
    float2 cs = float2((p.z - wav) / HZ, p.y / yScale);
    float body = (length(cs) - r) * min(HZ, HY * 0.90);
    body = max(body, max(p.x - 0.5, -0.5 - p.x));

    // ---- caudal fin -------------------------------------------------------------------
    // Two lobes rather than one vane with a notch cut out of it: a koi's tail is genuinely
    // forked and the lobes sit at slightly different angles. Hinged at the peduncle and carried
    // by the same wave but one step further along in phase, so it LAGS the body instead of being
    // welded to it — that lag is most of what makes the swim read as propulsion.
    float tailW = sin(beat - 4.6 - 0.55) * amp;
    float3 q = float3(p.x + 0.46, p.y, p.z - tailW);

    float3 qu = float3(tpRot2(q.xy, -0.40), q.z);
    float3 ql = float3(tpRot2(q.xy,  0.40), q.z);
    float caud = min(tpVaneXY(qu - float3(-0.135, 0.0, 0.0), float2(0.128, 0.026), 0.030, 0.0055),
                     tpVaneXY(ql - float3(-0.135, 0.0, 0.0), float2(0.128, 0.026), 0.030, 0.0055));

    // ---- dorsal ---------------------------------------------------------------------------
    // Long and low, running most of the back. A koi dorsal is a ridge, not a sail.
    float dorW = sin(beat - 2.30 - 0.30) * amp * tpFishSweep(0.5);
    float dor = tpVaneXY(float3(p.x - 0.02, p.y - 0.150, p.z - dorW),
                         float2(0.190, 0.018), 0.026, 0.0045);

    // ---- anal fin -------------------------------------------------------------------------
    float anW = sin(beat - 3.59 - 0.40) * amp * tpFishSweep(0.22);
    float anal = tpVaneXY(float3(p.x + 0.255, p.y + 0.132, p.z - anW),
                          float2(0.056, 0.016), 0.024, 0.0040);

    // ---- pectorals ------------------------------------------------------------------------
    // Paired, held out from the shoulders, nearly horizontal. Seen from above — which is how a
    // pool is seen — these are the strongest koi cue there is, and a fish without them reads as
    // a leech however good the body is. They scull gently, off the tail's phase.
    float scull = sin(beat * 0.75) * 0.16;
    float3 pr = float3(p.x - 0.175, p.y + 0.045, abs(p.z) - 0.068);
    pr.xz = tpRot2(pr.xz, -0.62);
    pr.y += pr.x * scull;
    float pect = tpVaneXZ(pr - float3(-0.072, 0.0, 0.0), float2(0.070, 0.028), 0.024, 0.0038);

    return min(min(body, caud), min(min(dor, anal), pect));
}

// ---------------------------------------------------------------------------
// The fish's own frame, exposed so a consumer can shade in BODY coordinates. The markings have
// to live in that space or they slide over the animal as it swims.
// ---------------------------------------------------------------------------
void tpFishFrame(TpFish f, out float3 fwd, out float3 up, out float3 rgt)
{
    fwd = normalize(f.dir);
    float3 up0 = (abs(fwd.y) > 0.94) ? float3(1, 0, 0) : float3(0, 1, 0);
    float3 r0 = normalize(cross(fwd, up0));
    float3 u0 = cross(r0, fwd);

    float cb = cos(f.bank), sb = sin(f.bank);
    up  = u0 * cb - r0 * sb;
    rgt = r0 * cb + u0 * sb;
}

float3 tpFishLocal(float3 wp, TpFish f)
{
    float3 fwd, up, rgt;
    tpFishFrame(f, fwd, up, rgt);
    float3 d = wp - f.pos;
    return float3(dot(d, fwd), dot(d, up), dot(d, rgt)) / max(f.len, 1e-4);
}

float tpFishSDF(float3 wp, TpFish f, float amp)
{
    return tpFishUnitSDF(tpFishLocal(wp, f), f.phase, amp) * max(f.len, 1e-4);
}

// ---------------------------------------------------------------------------
// KOI MARKINGS.
//
// A koi is not a coloured fish, it is a PATTERNED one, and the pattern is the animal: a white
// ground carrying hard-edged crimson blotches over the back and shoulders, with a sparser wash
// of black on the darker varieties.
//
// HARD EDGES ARE THE POINT. On a real koi the boundary between white and red is a step you
// could trace with a pen, and a soft airbrushed gradient there reads as a generic tropical fish
// instantly. Authored in body space so the markings stay put while the fish swims, and biased
// upward in coverage so the belly runs clean white the way a real one does.
// ---------------------------------------------------------------------------
float3 tpKoiColour(float3 lp, float seed, float3 red, float amount, float sumiAmt, out float metal)
{
    float s = saturate(lp.x + 0.5);

    // Two scales of blotch: the larger carries the composition, the smaller breaks its edges so
    // they do not read as the shape of the noise that made them.
    float n1 = tpVNoise(float2(s * 3.4 + seed * 1.7, lp.y * 4.6 + lp.z * 2.2 + seed * 0.9));
    float n2 = tpVNoise(float2(s * 7.1 - seed * 2.3, lp.z * 6.8 - lp.y * 1.7 + seed * 1.3));
    float patch = n1 * 0.70 + n2 * 0.30;

    // Coverage falls away toward the belly: markings sit on the back and shoulders.
    patch += saturate(lp.y * 2.6) * 0.22 - 0.10;

    float thr = lerp(0.74, 0.32, saturate(amount));
    float hi = smoothstep(thr - 0.030, thr + 0.030, patch);

    float3 white = float3(0.955, 0.945, 0.920);
    float3 c = lerp(white, red, hi);

    // Sumi: sparser, coarser, and always ON TOP — black sits over white and red alike.
    float n3 = tpVNoise(float2(s * 2.3 + seed * 3.1, lp.z * 3.9 + lp.y * 3.1 - seed * 2.7));
    float sumi = smoothstep(0.80 - saturate(sumiAmt) * 0.32, 0.86 - saturate(sumiAmt) * 0.32, n3);
    c = lerp(c, float3(0.075, 0.070, 0.080), sumi * saturate(sumiAmt));

    // The white ground on a koi is faintly pearlescent and the red is flatter. Handing that back
    // lets the renderer put the sheen where it belongs instead of glazing the whole animal.
    metal = lerp(1.0, 0.45, hi) * (1.0 - sumi * 0.5);
    return c;
}

// ---------------------------------------------------------------------------
// A CHEAP OCCLUDER, for shadows only.
//
// A soft underwater shadow is a blurred blob — it carries no fin detail and no tail wave, and
// nobody has ever looked at one and identified the dorsal. So paying for the full
// body-plus-five-fins field twice more per pixel buys nothing visible at all.
//
// It costs plenty, though. The full field is a large function and it is INLINED at every call
// site: once in the primary march, four times in the tetrahedral normal, and once per shadow
// march. At seven copies inside the AA loop the march shader took minutes to compile and the
// register pressure would have followed it. This is the body alone, slightly inflated to stand
// in for the fins, and because it has no domain bend it is also a well-behaved field the shadow
// march can step through much faster.
// ---------------------------------------------------------------------------
#define TP_FISH_SHADOW_STEP 0.85

float tpFishShadowSDF(float3 wp, TpFish f)
{
    float3 p = tpFishLocal(wp, f);
    float s = saturate(p.x + 0.5);
    float r = tpKoiProfile(s);
    float2 cs = float2(p.z / 0.105, p.y / 0.170);      // inflated: the fins shadow too
    float d = (length(cs) - r) * 0.105;
    d = max(d, max(p.x - 0.55, -0.55 - p.x));
    return d * max(f.len, 1e-4);
}

// Bounding radius, in world units. Generous enough to cover the caudal lobes at full sweep.
float tpFishRadius(TpFish f) { return f.len * 0.78; }

#endif // TP_FISH_HLSLI
