// VT_Growth / grow.hlsl — expands the plan's anchors into drawable limbs.
//
// Masses become parent-indexed capsule chains in world space (VT_Volumes ray-marches them).
// Strokes become parent-indexed polylines in stage space (VT_Strokes draws them as tubes).
// One buffer, `role` discriminates, and both halves publish a group header carrying a bounding
// sphere so the ray-marcher can reject a whole mass with one test instead of touching nodes.
//
// Single-threaded: ~700 records of sequential work, noise next to any render pass, and the
// parent-index topology genuinely needs to be built in order.
#include "../_shared/vitrine.hlsli"

StructuredBuffer<PlanRec> Plan : register(t0);
RWStructuredBuffer<LimbRec> Limbs : register(u0);

// growth topology modes
#define G_BRANCH  0
#define G_TENDRIL 1
#define G_CORAL   2
#define G_BUNDLE  3

float3 randUnit(float s)
{
    float3 h = vt_hash33(float3(s * 1.7 + 0.31, s * 2.9 + 5.13, s * 0.73 + 11.7));
    float z = h.x * 2.0 - 1.0;
    float a = h.y * 6.2831853;
    float r = sqrt(max(1.0 - z * z, 0.0));
    return float3(r * cos(a), r * sin(a), z);
}

void clearRec(uint i)
{
    LimbRec e = (LimbRec)0;
    e.parent = -1.0;
    e.active = 0.0;
    Limbs[i] = e;
}

// EVERY record store goes through here.
//
// Building the struct field-by-field at the call site produced records whose pos/radius/
// parent/tparam were correct but whose group/kind/material/seed still held the PREVIOUS
// anchor's values — the identity fields are the ones only read inside the growth loop, and
// fxc was hoisting them out of the inlined per-anchor bodies. Forcing every field through an
// explicit float argument gives it nothing to hoist.
void writeLimb(uint slot, float3 pos, float radius, float parent, float grp,
               float role, float mat, float tp, float sd, float kd)
{
    LimbRec r;
    r.pos = pos;
    r.radius = radius;
    r.parent = parent;
    r.group = grp;
    r.role = role;
    r.material = mat;
    r.tparam = tp;
    r.seed = sd;
    r.kind = kd;
    r.active = 1.0;
    Limbs[slot] = r;
}

void writeHeader(uint slot, float3 pos, float radius, float first, float count,
                 float mat, float depth, float sd, float kd, float alive)
{
    LimbRec h;
    h.pos = pos;
    h.radius = radius;
    h.parent = first;
    h.group = count;
    h.role = LROLE_HEADER;
    h.material = mat;
    h.tparam = depth;
    h.seed = sd;
    h.kind = kd;
    h.active = alive;
    Limbs[slot] = h;
}

// ---------------------------------------------------------------------------
// Per-archetype directional bias. This is what makes a melt melt and arms reach — the growth
// MODE controls topology, the archetype controls where the material wants to go.
// ---------------------------------------------------------------------------
float3 archetypeBias(int kind, float depth, float t, float sd)
{
    if (kind == MK_MELT)   return float3(0.0, -1.0, 0.0) * (0.35 + 0.75 * t);
    if (kind == MK_ARMS)   return float3(0.0, 1.0, 0.0) * (depth < 3.0 ? 0.95 : 0.45)
                                + float3(sign(vt_rnd(sd, 2.0) - 0.5) * 0.55 * t, 0.0, 0.0);
    if (kind == MK_HAND)   return normalize(float3((vt_rnd(sd, 3.0) - 0.5) * 1.6, 0.85, 0.0)) * 0.7;
    if (kind == MK_STAR)   return float3(0.0, 0.0, 0.0);
    if (kind == MK_RIBBON) return float3(0.0, 0.0, 0.0);
    return float3(0.0, 0.0, 0.0);
}

// ---------------------------------------------------------------------------
// Masses
// ---------------------------------------------------------------------------
void growMass(uint hdrIdx, PlanRec p, uint first, uint count)
{
    int kind = (int)p.kind;
    uint mat = ((uint)p.flags >> 8) & 15u;
    float sd = p.seed;
    float w = vt_depthW(p.grp);
    float3 root = vt_toWorld(p.pos, p.grp);

    // Every magnitude below derives from the reserve the PLAN cleared for this mass. Giving
    // the grower its own size parameter would create two numbers to keep in agreement.
    // `size.x` (the reserve) is the object's footprint and the ONLY size input. `size.y` is a
    // node-budget share and deliberately does not enter the geometry — folding it in here made
    // every magnitude depend on two numbers and shrank the small archetypes to dots.
    // Radius-to-bond ratio is what decides whether a chain reads as an ARTICULATED limb or as
    // one fused lump. At 0.83 every pair of nodes overlapped almost completely and the melt
    // came out a smooth horseshoe; ~0.43 keeps the tube continuous while the lobes stay legible.
    // Radius-to-bond ratio is what decides whether a chain reads as an ARTICULATED limb or as
    // one fused lump. At 0.83 every pair of nodes overlapped almost completely and the melt
    // came out a smooth horseshoe; ~0.31 keeps the tube continuous while the lobes stay legible.
    //
    // Node COUNT matters just as much: 50 nodes inside one containment disc always packs into a
    // ball no matter how the directions are chosen. The reference's figures are ~15-node trees,
    // so the budget is deliberately small and `bond * depth` is sized to just reach the reserve.
    float reserve = max(p.size.x, 0.02) * 2.0 * w;
    float archR = (kind == MK_MELT) ? 1.70 : ((kind == MK_HAND) ? 1.35 : ((kind == MK_STAR) ? 0.85 : 1.0));
    float rootR = reserve * 0.105 * radius_root * archR;
    float bond = reserve * 0.340 * bond_len;

    int mode = (int)growth_mode;
    float reveal = saturate(growth);
    uint live = max((uint)(round((float)count * reveal)), 1u);

    float boundR = rootR;

    // ---- root
    writeLimb(first, root, rootR, -1.0, (float)hdrIdx, LROLE_MASS, (float)mat, 0.0, sd, (float)kind);

    // [loop] is mandatory here, not a hint. This loop READS BACK records it wrote on earlier
    // iterations (parent lookups), and letting fxc partially unroll a dynamic-trip-count loop
    // over a UAV produced records whose pos/parent/tparam were right but whose
    // group/kind/material/seed were stale or zero.
    [loop]
    for (uint i = 1u; i < count; i++)
    {
        uint slot = first + i;
        if (i >= live) { clearRec(slot); continue; }

        float ns = sd + (float)i * 3.77;
        float t = (float)i / max((float)count - 1.0, 1.0);

        // ---- topology: who is my parent?
        uint par;
        if (kind == MK_BLOB || kind == MK_RIBBON) par = i - 1u;          // explicit curves below
        else if (kind == MK_STAR)                 par = (i <= 6u) ? 0u : (i - 6u);
        else if (mode == G_TENDRIL)               par = i - 1u;
        else if (mode == G_BUNDLE)                par = (i < 5u) ? 0u : (i - 5u);
        else if (mode == G_CORAL)                 par = (uint)(vt_rnd(ns, 1.0) * (float)i * 0.55);
        else                                      par = (uint)max((float)((i - 1u) / 2u), 0.0);
        par = min(par, i - 1u);

        // Single exit. The BLOB and RIBBON archetypes previously computed their point and
        // `continue`d before the general path; with a large trip count fxc dropped every
        // iteration of those two branches and only their root record survived, which the
        // group tally in the preview shows as a short red bar. Every archetype now falls
        // through to ONE writeLimb at the bottom of the loop.
        float3 pt;
        float rr;

        if (kind == MK_BLOB)
        {
            // A closed ring of fat spheres. Smooth-unioned downstream this becomes a soft body
            // with a real hole through it — the reference's frosted blob, not a lump.
            float a = 6.2831853 * (float)i / max((float)count, 2.0);
            float ring = reserve * 0.62;
            float lob = 1.0 + 0.30 * sin(a * 3.0 + sd);
            pt = root + float3(cos(a) * ring * 1.05 * lob, sin(a) * ring * 0.92 * lob,
                               sin(a * 2.0 + sd) * ring * 0.30);
            rr = ring * 0.40 * radius_root;
        }
        else if (kind == MK_RIBBON)
        {
            // A gestural S-stroke: fat at the ends, pinched in the middle. This is the shape
            // that reads as liquid chrome once it is mirrored.
            float u = t * 2.0 - 1.0;
            float ln = reserve * 1.30;
            float bendA = (vt_rnd(sd, 4.0) - 0.5) * 2.4;
            pt = root + float3(u * ln * 0.55 + sin(u * 3.1 + sd) * ln * 0.30,
                               sin(u * 2.35 + bendA) * ln * 0.62,
                               cos(u * 1.7 + sd) * ln * 0.16);
            float prof = 0.42 + 0.58 * abs(u) * abs(u);
            rr = ln * 0.16 * prof * radius_root;
        }
        else
        {
            LimbRec pr = Limbs[first + par];
            float3 ppos = pr.pos;
            float pdepth = pr.tparam * (float)depth_max;

            // parent's own heading, from ITS parent. A root has none, so the first generation
            // is distributed on a sphere — inheriting a default up-vector grows every cluster
            // one-sided.
            float3 pdir;
            if (pr.parent < 0.0)
                pdir = normalize(randUnit(sd + (float)i * 0.91) + float3(0.0, 0.3, 0.0));
            else
                pdir = normalize(pr.pos - Limbs[(uint)pr.parent].pos + float3(1e-5, 1e-5, 1e-5));
            if (kind == MK_STAR && i <= 6u)
                pdir = normalize(float3(cos((float)i * 1.047 + sd),
                                        sin((float)i * 1.047 + sd) * 1.2,
                                        0.25 * (vt_rnd(ns, 8.0) - 0.5)));

            float3 jitterDir = randUnit(ns);
            float3 bias = archetypeBias(kind, pdepth, t, sd + (float)par);

            float3 dir;
            float len;
            if (mode == G_BUNDLE)
            {
                // strands run parallel to the parent with a lateral offset — a fibrous bundle
                float3 side = normalize(cross(pdir, float3(0, 0, 1)) + 1e-4);
                dir = normalize(pdir * 1.2 + side * (vt_rnd(ns, 5.0) - 0.5) * spread * 0.8 + bias * 0.4);
                len = bond * 1.15;
            }
            else if (mode == G_CORAL)
            {
                // REPAIRED after the exploration sweep. Short bonds plus heavy jitter packed
                // every cluster into a featureless potato. Radiating OUTWARD from the root with
                // a near-full bond gives the knobbly coral head the preset was named for.
                float3 outward = normalize(ppos - root + float3(1e-4, 1e-4, 1e-4));
                dir = normalize(outward * 1.20 + pdir * persistence * 0.35
                                + jitterDir * spread * 1.15 + bias * 0.5);
                len = bond * 0.95;
            }
            else if (mode == G_TENDRIL)
            {
                float curl = (float)i * 0.42 + sd;
                float3 side = normalize(cross(pdir, float3(0, 0, 1)) + 1e-4);
                float3 up = cross(side, pdir);
                dir = normalize(pdir * (persistence + 0.5) + (side * cos(curl) + up * sin(curl)) * wander * 0.9 + bias * 0.5);
                len = bond * 1.25;
            }
            else
            {
                dir = normalize(pdir * persistence + jitterDir * spread + bias);
                len = bond;
            }

            pt = ppos + dir * len;

            // Soft containment inside the reserve the plan cleared. Without it whole clusters
            // march off the stage; with it they fill their disc.
            float3 rel = pt - root;
            float dist = length(rel);
            float limit = reserve * containment;
            if (dist > limit)
                pt = root + rel * (limit / max(dist, 1e-5)) * lerp(1.0, 0.92, saturate((dist - limit) / limit));

            // Radius tapers over the first generations, then HOLDS. Letting radius decay
            // geometrically forever collapses every branch onto its own root.
            float gen = t * (float)depth_max;
            float rad = rootR * max(pow(radius_decay, gen), 0.30);
            if (kind == MK_HAND) rad *= lerp(1.25, 0.55, t);
            if (kind == MK_MELT) rad *= 1.0 + 0.45 * sin(t * 9.0 + sd) * bud_swell;
            if (kind == MK_ARMS) rad *= lerp(1.0, 0.62, t);
            rad *= 1.0 + 0.12 * breathe * sin(_Time * anim_rate * 1.7 + p.phase * 6.28 + t * 4.0);
            rr = max(rad, rootR * 0.12);
        }

        writeLimb(slot, pt, rr, (float)(first + par), (float)hdrIdx, LROLE_MASS,
                  (float)mat, t, ns, (float)kind);

        boundR = max(boundR, length(pt - root) + rr);
    }

    writeHeader(hdrIdx, root, boundR * 1.06, (float)first, (float)live,
                (float)mat, p.grp, sd, (float)kind, 1.0);
}

// ---------------------------------------------------------------------------
// Strokes — 2D polylines in stage space
// ---------------------------------------------------------------------------
void growStroke(uint hdrIdx, PlanRec p, uint first, uint count)
{
    int kind = (int)p.kind;
    float sd = p.seed;
    float2 c = p.pos;
    float2 e = max(p.size, 0.006);
    // ABSOLUTE base radius, not a fraction of the extent: how thick a stroke is has nothing to
    // do with how far it wanders, and scaling by the extent turned the wide black vein network
    // into a solid blob while leaving the tight hairlines sub-pixel.
    float weight = max(p.phase, 0.02);
    float baseW = 0.014 * weight * tube_scale;

    float reveal = saturate(growth);
    uint live = max((uint)(round((float)count * reveal)), 2u);
    float boundR = 0.0;

    uint strands = 1u;
    if (kind == SK_BUNDLE) strands = (uint)clamp((float)bundle_strands, 2.0, 8.0);

    uint perStrand = max(count / strands, 2u);
    float rot = (vt_rnd(sd, 11.0) - 0.5) * 1.2;

    [loop]
    for (uint i = 0u; i < count; i++)
    {
        uint slot = first + i;
        if (i >= live) { clearRec(slot); continue; }

        uint strand = min(i / perStrand, strands - 1u);
        uint k = i - strand * perStrand;
        float t = saturate((float)k / max((float)perStrand - 1.0, 1.0));
        float ss = sd + (float)strand * 19.3;

        float2 q;
        float ww = 1.0;
        bool isStart = (k == 0u);

        if (kind == SK_BUNDLE)
        {
            // parallel wavy strands — the reference's rainbow verticals and orange horizontals
            float lane = ((float)strand / max((float)strands - 1.0, 1.0)) - 0.5;
            float a = t * 2.0 - 1.0;
            q = float2(lane * 1.55 + sin(a * 3.1 + ss) * 0.42 * squiggle,
                       a * 1.0);
            ww = 0.85 + 0.3 * sin(t * 3.14159);
        }
        else if (kind == SK_ARC)
        {
            float a = t * 2.0 - 1.0;
            q = float2(sin(a * 1.45 + rot) * 0.92, a);
            ww = 0.5 + 0.75 * sin(t * 3.14159);
        }
        else if (kind == SK_SQUIGGLE)
        {
            float a = t * 2.0 - 1.0;
            q = float2(a, sin(a * (3.2 + 2.4 * vt_rnd(sd, 2.0)) + ss) * 0.72 * squiggle);
            q = vt_rot2(q, rot);
            ww = 0.7 + 0.5 * sin(t * 3.14159);
        }
        else if (kind == SK_TANGLE)
        {
            float a = t * 6.2831853 * (1.0 + floor(vt_rnd(sd, 3.0) * 2.0));
            float rr = 0.55 + 0.42 * sin(a * 1.7 + ss);
            q = float2(cos(a) * rr, sin(a * 1.35 + ss) * rr);
            ww = 0.8;
        }
        else // SK_BRANCH — a 2D vein network, parent-indexed
        {
            uint par = (i == 0u) ? 0u : (uint)max((float)((i - 1u) / 2u), 0.0);
            float2 ppos = (i == 0u) ? float2(0.0, 0.0)
                                    : (Limbs[first + par].pos.xy - c) / e;
            float ang = (vt_rnd(sd + (float)i, 4.0) - 0.5) * 2.2 * branch_spread
                      + atan2(ppos.y + 1e-4, ppos.x + 1e-4);
            float step = 0.34 / (1.0 + 0.35 * (float)((i) / 3u));
            q = ppos + float2(cos(ang), sin(ang)) * step;
            q = clamp(q, -1.15, 1.15);
            ww = lerp(1.25, 0.42, saturate((float)i / max((float)count - 1.0, 1.0)));
            isStart = (i == 0u);
        }

        float2 sp = c + q * e;
        float2 rel = sp - c;
        boundR = max(boundR, length(rel));

        // hue: bundles run a rainbow across their strands, everything else keeps the plan's tone
        float tone = p.tone;
        if (kind == SK_BUNDLE) tone = frac(p.tone + (float)strand * rainbow / max((float)strands, 1.0));

        float parIdx = -1.0;
        if (kind == SK_BRANCH) parIdx = (i == 0u) ? -1.0 : (float)(first + (uint)max((float)((i - 1u) / 2u), 0.0));
        else                   parIdx = isStart ? -1.0 : (float)(slot - 1u);

        writeLimb(slot, float3(sp, p.grp), baseW * ww, parIdx, (float)hdrIdx,
                  LROLE_STROKE, tone, t, sd + (float)i, (float)kind);
    }

    writeHeader(hdrIdx, float3(c, p.grp), boundR + baseW * 2.0, (float)first, (float)live,
                p.tone, p.grp, sd, (float)kind, 1.0);
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    // ---- budget masses proportionally to the growth scale the plan gave them
    float scaleSum = 0.0;
    uint liveMass = 0u;
    for (uint a = 0u; a < PLAN_MASSES; a++)
    {
        PlanRec p = Plan[PLAN_MASS_0 + a];
        if (p.active > 0.5) { scaleSum += max(p.size.y, 0.05); liveMass++; }
    }
    uint massPool = min((uint)max(mass_budget, 16), LIMB_MASS_CAP - LIMB_NODE_0);

    uint cursor = LIMB_NODE_0;
    for (uint m = 0u; m < PLAN_MASSES; m++)
    {
        PlanRec p = Plan[PLAN_MASS_0 + m];
        uint hdr = LIMB_MASS_H_0 + m;
        if (p.active < 0.5 || scaleSum <= 0.0)
        {
            writeHeader(hdr, float3(0,0,0), 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
            continue;
        }
        uint want = (uint)max(floor((float)massPool * max(p.size.y, 0.05) / scaleSum), 6.0);
        want = min(want, LIMB_MASS_CAP - cursor);
        if (want < 3u)
        {
            writeHeader(hdr, float3(0,0,0), 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
            continue;
        }
        growMass(hdr, p, cursor, want);
        cursor += want;
    }
    for (uint z = cursor; z < LIMB_MASS_CAP; z++) clearRec(z);

    // ---- strokes get their own partition so a heavy mass cast cannot starve them
    uint liveStroke = 0u;
    for (uint b = 0u; b < PLAN_STROKES; b++)
        if (Plan[PLAN_STROKE_0 + b].active > 0.5) liveStroke++;

    uint strokePool = min((uint)max(stroke_budget, 16), LIMB_RECORDS - LIMB_STROKE_0);
    uint scursor = LIMB_STROKE_0;
    uint per = (liveStroke > 0u) ? (strokePool / liveStroke) : 0u;

    for (uint s = 0u; s < PLAN_STROKES; s++)
    {
        PlanRec p = Plan[PLAN_STROKE_0 + s];
        uint hdr = LIMB_STROKE_H_0 + s;
        if (p.active < 0.5 || per < 3u)
        {
            writeHeader(hdr, float3(0,0,0), 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
            continue;
        }
        uint want = min(per, LIMB_RECORDS - scursor);
        if (want < 3u)
        {
            writeHeader(hdr, float3(0,0,0), 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
            continue;
        }
        growStroke(hdr, p, scursor, want);
        scursor += want;
    }
    for (uint y = scursor; y < LIMB_RECORDS; y++) clearRec(y);
}
