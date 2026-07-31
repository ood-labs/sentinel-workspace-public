// mx_organism / grow.hlsl — grows the molecular trees the plate's organism anchors call for.
//
// Bonds are implicit: every node stores its parent index, so one buffer carries both the
// spheres and the tubes between them. That is also what the structures actually are — the
// reference's masses are branching trees, not arbitrary graphs.
//
// Stateless by design. The whole field is rebuilt from (anchor records + parameters + _Time)
// every cook, so there is no persistence to invalidate and animation is just part of the
// generator. Single-threaded because breadth-first growth is inherently sequential; the work
// is ~1500 iterations, which is nothing next to any render pass.
#include "../_shared/plate.hlsli"

struct MolNode
{
    float3 pos;      // world space
    float  radius;
    float  parent;   // index of parent node, -1 at a root
    float  xlink;    // reserved second bond, -1 when unused
    float  cluster;  // owning anchor
    float  depth;    // generation in the tree
    float  seed;
    float  phase;
    float  kind;     // 1 = junction (has children), 2 = terminal bud
    float  active;
};

RWStructuredBuffer<MolNode> Nodes : register(u0);
// _Data0 = the Plate records published by MX_Console.

#define NODE_CAP 320u

// PLATE SPACE -> world. Defined once, here, because this is the node that leaves 2D.
// The plate's unit square becomes world [-1,1] on X and Y, y flipped to world-up.
float3 plateToWorld(float2 p, float z) { return float3((p.x - 0.5) * 2.0, -(p.y - 0.5) * 2.0, z); }

void growCluster(PlateRec an, uint cid, inout uint cursor, uint endCap, float t)
{
    int gk = (int)(an.kind + 0.5);
    float s = an.seed;
    float3 origin = plateToWorld(an.pos, 0.0);

    uint start = cursor;

    // Bond length is CONSTANT across the tree, and radius tapers only over the first few
    // generations before holding. Letting bond length follow a geometric radius decay makes
    // every branch converge on its own root and the mass collapses into a knot; the reference's
    // masses are near-uniform spheres on comparable bonds, which is what this produces.
    // The step is sized off the reserve disc the console cleared, so growth scales with layout.
    float reserveW = max(an.size.x, 0.02) * 2.0;
    float bondL = reserveW / 6.0 * spacing;
    if (gk == G_CHAIN) bondL *= 1.25;  // backbones carry visibly longer tubes than dendrites
    float maxR = reserveW * 0.5 * containment;

    // A backbone reads as a few large masses; a dendrite reads as many small ones. Same
    // growth code, different sphere-to-bond ratio, which is what separates the reference's
    // central molecule from its coral-like corner clusters.
    float kindSize = (gk == G_CHAIN) ? 0.78 : 0.58;

    MolNode root;
    root.pos     = origin;
    root.radius  = bondL * node_size * kindSize * 1.25 * radius_root;
    root.parent  = -1.0;
    root.xlink   = -1.0;
    root.cluster = (float)cid;
    root.depth   = 0.0;
    root.seed    = s;
    root.phase   = mxRnd(s, 1.0);
    root.kind    = 2.0;
    root.active  = 1.0;
    Nodes[cursor++] = root;

    // A chain spends one generation per node, so it needs far more depth than a dendrite to
    // reach a comparable length. The node budget still bounds it.
    uint dmax = (uint)clamp((float)depth_max, 1.0, 24.0);
    if (gk == G_CHAIN) dmax = min(dmax * 4u, 80u);

    uint q = start;
    uint guard = 0u;

    while (q < cursor && cursor < endCap && guard < 512u)
    {
        guard++;
        MolNode p = Nodes[q];
        uint d = (uint)p.depth;
        if (d >= dmax) { q++; continue; }

        // direction the branch arrived from, so growth carries momentum instead of scattering
        float3 indir = float3(0.0, 1.0, 0.0);
        if (p.parent >= 0.0) indir = normalize(p.pos - Nodes[(uint)p.parent].pos + 1e-5);

        uint kids;
        if (gk == G_CHAIN)
            kids = (mxRnd(p.seed, 21.0) < 0.28 && d > 1u) ? 2u : 1u;     // meandering backbone
        else if (gk == G_BURST)
            kids = (d == 0u) ? (uint)(6.0 + 4.0 * mxRnd(s, 3.0))
                             : ((mxRnd(p.seed, 22.0) < 0.30) ? 2u : 1u);  // hub and spokes
        else
            kids = (d == 0u) ? 4u : ((mxRnd(p.seed, 23.0) < 0.55) ? 3u : 2u); // dendrite

        uint added = 0u;
        for (uint k = 0u; k < kids && cursor < endCap; k++)
        {
            float2 h = mxHash22(float2(p.seed * 3.1 + (float)k * 7.7, (float)d * 2.3 + s));
            float az = (h.x - 0.5) * 6.2831853 * spread;
            float el = (h.y - 0.5) * 3.14159265 * spread;
            float3 off = float3(cos(az) * cos(el), sin(el), sin(az) * cos(el));

            // Branches must carry outward momentum. With low persistence children scatter back
            // across the parent and the cluster fuses into a featureless ball.
            float persist = (gk == G_CHAIN) ? (1.0 / max(wander, 0.05)) : 1.5;
            float3 dir;
            if (d == 0u && gk != G_CHAIN)
            {
                // The root has no incoming direction, so inheriting a default up-vector throws
                // the whole cluster to one side. Spread the first generation evenly over a
                // sphere (Fibonacci) and let persistence take over from generation 1.
                float zz = 1.0 - 2.0 * ((float)k + 0.5) / (float)kids;
                float rr = sqrt(max(1.0 - zz * zz, 0.0));
                float aa = 2.39996323 * (float)k + mxRnd(s, 77.0) * 6.2831853;
                dir = normalize(float3(rr * cos(aa), zz, rr * sin(aa)) + off * 0.25);
            }
            else
            {
                // mild outward bias so a dendrite opens like coral instead of tangling
                float3 outward = normalize(p.pos - origin + float3(1e-4, 1e-4, 1e-4));
                float bias = (gk == G_CHAIN) ? 0.0 : 0.65;
                dir = indir * persist + off + outward * bias;
            }
            // Soft containment: as a branch approaches the edge of its reserve disc, steer it
            // back inward. Without this, persistence marches whole clusters off the plate at
            // higher bond lengths; a hard clamp instead would pile every tip on one shell.
            float3 rel = p.pos - origin;
            float rl = length(rel);
            float over = saturate((rl / max(maxR, 1e-4) - 0.70) / 0.35);
            dir = lerp(dir, -normalize(rel + float3(1e-4, 1e-4, 1e-4)), over * 0.75);

            dir.z *= flatten;                  // squash toward the plate so the mass reads flat-ish
            dir = normalize(dir + float3(0.0, 0.0, 1e-5));

            // taper holds after ~8 generations so deep dendrites keep readable spheres
            float taper = pow(radius_decay, min((float)(d + 1u), 8.0));
            float cr  = bondL * node_size * kindSize * radius_root
                      * lerp(0.78, 1.22, mxRnd(p.seed + (float)k, 31.0))
                      * (0.45 + 0.55 * taper);
            float len = bondL * lerp(0.85, 1.15, mxRnd(p.seed + (float)k, 41.0));

            MolNode n;
            n.pos     = p.pos + dir * len;
            n.radius  = cr;
            n.parent  = (float)q;
            n.xlink   = -1.0;
            n.cluster = (float)cid;
            n.depth   = (float)(d + 1u);
            n.seed    = p.seed * 1.7 + (float)k * 13.9 + 5.0;
            n.phase   = mxRnd(n.seed, 2.0);
            n.kind    = 2.0;
            n.active  = 1.0;
            Nodes[cursor++] = n;
            added++;
        }

        if (added > 0u) { MolNode pu = Nodes[q]; pu.kind = 1.0; Nodes[q] = pu; }
        q++;
    }

    // Second sweep: swell the terminal buds, apply the growth reveal, then spin and breathe
    // the whole cluster around its own anchor.
    float gd = growth * (float)dmax;
    float spinAng = t * spin * lerp(0.6, 1.4, mxRnd(s, 9.0)) * ((gk == G_CHAIN) ? 0.45 : 1.0);
    float ca = cos(spinAng), sa = sin(spinAng);

    for (uint i = start; i < cursor; i++)
    {
        MolNode n = Nodes[i];
        if (n.kind > 1.5) n.radius *= bud_swell;

        float f = saturate(gd - n.depth + 1.0);
        if (f <= 0.02) { n.active = 0.0; Nodes[i] = n; continue; }
        n.radius *= f;

        float3 rel = n.pos - origin;
        rel = float3(ca * rel.x + sa * rel.z, rel.y, -sa * rel.x + ca * rel.z);
        // breathing travels outward along the tree rather than pulsing everything in unison
        rel *= 1.0 + breathe * 0.10 * sin(t * 2.1 - n.depth * 0.55 + n.phase * 6.2831853);
        n.pos = origin + rel;
        n.radius *= 1.0 + breathe * 0.09 * sin(t * 1.7 + n.phase * 6.2831853);

        Nodes[i] = n;
    }
}

// Budget share. Dendrites need many more records than a backbone to read as coral, so the
// split follows growth kind as well as the anchor's authored scale.
float anchorWeight(PlateRec an)
{
    return max(an.size.y, 0.05) * (((int)(an.kind + 0.5) == G_CHAIN) ? 1.0 : 1.9);
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    for (uint c = 0u; c < NODE_CAP; c++)
    {
        MolNode z = (MolNode)0;
        z.parent = -1.0; z.xlink = -1.0; z.active = 0.0;
        Nodes[c] = z;
    }

    float totalW = 0.0;
    for (uint a = 0u; a < 8u; a++)
    {
        PlateRec an = _Data0[PLATE_ANCHOR_0 + a];
        if (an.role > 0.5 && an.role < 1.5 && an.active > 0.5) totalW += anchorWeight(an);
    }
    if (totalW <= 1e-5) return;

    uint cursor = 0u;
    uint cap = min((uint)node_budget, NODE_CAP);
    float t = _Time * anim_rate;

    for (uint b = 0u; b < 8u; b++)
    {
        PlateRec an = _Data0[PLATE_ANCHOR_0 + b];
        if (!(an.role > 0.5 && an.role < 1.5 && an.active > 0.5)) continue;
        // budget follows the anchor's authored growth scale, so the hero mass stays the hero
        uint quota = (uint)max(8.0, floor((float)cap * anchorWeight(an) / totalW));
        uint endCap = min(cursor + quota, cap);
        if (cursor >= endCap) break;
        growCluster(an, b, cursor, endCap, t);
    }
}
