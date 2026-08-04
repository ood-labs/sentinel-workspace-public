// VC_Plan / plan.hlsl — authors the whole vitreous_cross composition into one durable buffer.
//
// Single-threaded on purpose: the layout is sequential and the viewport event queue has to be
// reduced in order. 48 records is nothing next to a refraction march.
//
// Regeneration is SIGNATURE-DRIVEN. Only structural parameters are in the signature; pure
// appearance refreshes in place every cook, so a tint tweak never costs the user the layout
// work they did by hand. Shader edits are invisible to the signature — bump PLAN_VERSION or a
// recompile silently keeps serving the previously generated plan.
#include "../_shared/vitreous.hlsli"

RWStructuredBuffer<VcRec> Plan : register(u0);

#define PLAN_VERSION 3.4

// ---------------------------------------------------------------------------
// The reference, transcribed. Stage space: x in [-1.5,1.5] right, y in [-1,1] up,
// z toward the viewer. Every number below was read off the reference image and converted
// with x = (u - 0.5) * 3, y = (0.5 - v) * 2.
// ---------------------------------------------------------------------------

// --- slabs: the interlocking glass volumes that make the cross silhouette
static const float3 SLAB_POS[12] = {
    float3(-1.035,  0.290,  0.000),   // 0 left cube
    float3(-0.780,  0.390, -0.100),   // 1 upper-left column (holds the top bubbles)
    float3(-0.375,  0.330,  0.140),   // 2 upper horizontal bar
    float3(-0.045,  0.040, -0.060),   // 3 lower horizontal bar, the long one
    float3( 0.630,  0.495,  0.100),   // 4 amber column
    float3( 0.960,  0.515, -0.040),   // 5 right column
    float3( 0.622, -0.205,  0.020),   // 6 lower column, runs off the bottom
    float3( 1.215,  0.160,  0.160),   // 7 right end block
    float3(-0.780, -0.290,  0.060),   // 8 bottom-left box
    float3(-1.280, -0.130, -0.140),   // 9  spare
    float3( 0.180,  0.640,  0.060),   // 10 spare
    float3( 0.060, -0.560, -0.100)    // 11 spare
};
static const float3 SLAB_HALF[12] = {
    float3(0.435, 0.350, 0.330),
    float3(0.210, 0.550, 0.260),
    float3(1.035, 0.190, 0.230),
    float3(1.185, 0.140, 0.310),
    float3(0.175, 0.415, 0.215),
    float3(0.195, 0.415, 0.250),
    float3(0.248, 0.605, 0.245),
    float3(0.150, 0.260, 0.190),
    float3(0.255, 0.270, 0.240),
    float3(0.170, 0.220, 0.200),
    float3(0.230, 0.180, 0.210),
    float3(0.300, 0.190, 0.220)
};
static const float SLAB_MAT[12] = {
    MAT_CLEAR, MAT_CLEAR, MAT_CLEAR, MAT_CLEAR, MAT_AMBER, MAT_CLEAR,
    MAT_CLEAR, MAT_CLEAR, MAT_CLEAR, MAT_SMOKE, MAT_CLEAR, MAT_AMBER
};

// --- inclusions: the organic mass. Air cavities inside the glass, which is why they lens.
//
// Authored as FIVE NAMED CLUSTERS rather than as a scatter, because that is how the reference
// is organised: a flowing central mass riding the long bar, a bulge escaping bottom-left, a
// second escaping bottom-centre, a small crown in the tall upper-left column, and a couple of
// isolated bubbles in the right-hand blocks. Sizes descend within each cluster so every group
// has one dominant lobe — that hierarchy is what stops a cluster reading as gravel.
static const float3 INC_POS[24] = {
    // A — the central flowing mass, riding the long bar
    float3(-0.520,  0.300,  0.040), float3(-0.240,  0.160, -0.060),
    float3( 0.000,  0.050,  0.060), float3( 0.220,  0.140, -0.020),
    float3(-0.380,  0.020,  0.020), float3(-0.080,  0.300,  0.100),
    float3( 0.140, -0.060, -0.080),
    // B — the bottom-left bulge, breaking out of the glass
    float3(-0.860, -0.300,  0.060), float3(-1.080, -0.100, -0.020),
    float3(-0.660, -0.500,  0.020), float3(-0.940, -0.580,  0.080),
    float3(-0.600, -0.200, -0.060),
    // C — the bottom-centre bulge, wrapping the lower column
    float3( 0.440, -0.400,  0.000), float3( 0.660, -0.620,  0.050),
    float3( 0.860, -0.340, -0.040), float3( 0.520, -0.720, -0.020),
    float3( 0.800, -0.060,  0.060),
    // D — the crown in the tall upper-left column
    float3(-0.800,  0.720,  0.000), float3(-0.660,  0.880, -0.060),
    float3(-0.900,  0.520,  0.050),
    // E — the right end block
    float3( 1.220,  0.100,  0.020), float3( 1.300, -0.100, -0.050),
    // F — trapped inside the left cube
    float3(-1.120,  0.340, -0.020), float3(-1.240,  0.140,  0.060)
};
static const float3 INC_RAD[24] = {
    float3(0.300, 0.260, 0.240), float3(0.270, 0.240, 0.220),
    float3(0.240, 0.220, 0.200), float3(0.210, 0.190, 0.180),
    float3(0.220, 0.200, 0.190), float3(0.180, 0.170, 0.160),
    float3(0.190, 0.180, 0.160),
    float3(0.290, 0.260, 0.240), float3(0.220, 0.200, 0.190),
    float3(0.240, 0.220, 0.200), float3(0.190, 0.180, 0.160),
    float3(0.170, 0.160, 0.150),
    float3(0.260, 0.230, 0.210), float3(0.240, 0.220, 0.200),
    float3(0.200, 0.190, 0.170), float3(0.180, 0.170, 0.150),
    float3(0.160, 0.150, 0.140),
    float3(0.200, 0.180, 0.170), float3(0.150, 0.140, 0.130),
    float3(0.160, 0.150, 0.140),
    float3(0.190, 0.180, 0.160), float3(0.130, 0.120, 0.110),
    float3(0.230, 0.210, 0.190), float3(0.170, 0.160, 0.150)
};

// --- panels: the flat graphic plates. Real opaque slabs seen THROUGH the glass, which is
// what gives the reference its hard-edged black and white rectangles.
static const float3 PANEL_POS[10] = {
    float3(-0.960,  0.235, -0.020),   // 0 black rectangle, left of centre
    float3( 0.900,  0.235, -0.020),   // 1 black rectangle, right of centre
    float3(-0.770,  0.800, -0.140),   // 2 white plate, top left
    float3(-0.795, -0.390,  0.020),   // 3 white plate, bottom left
    float3( 0.570,  0.480,  0.080),   // 4 copper plate in the amber column
    float3( 0.475, -0.500,  0.100),   // 5 copper plate, lower column
    float3( 1.005,  0.640, -0.100),   // 6 white plate, top right
    float3(-0.300,  0.330,  0.180),   // 7 white plate on the upper bar face
    float3( 1.230,  0.060,  0.140),   // 8 spare
    float3(-1.150,  0.400,  0.240)    // 9 spare
};
static const float3 PANEL_HALF[10] = {
    float3(0.195, 0.115, 0.012),
    float3(0.203, 0.115, 0.012),
    float3(0.170, 0.150, 0.012),
    float3(0.195, 0.190, 0.012),
    float3(0.082, 0.400, 0.012),
    float3(0.130, 0.320, 0.012),
    float3(0.135, 0.240, 0.012),
    float3(0.560, 0.160, 0.012),
    float3(0.110, 0.170, 0.012),
    float3(0.150, 0.180, 0.012)
};
static const float PANEL_MAT[10] = {
    MAT_BLACK, MAT_BLACK, MAT_WHITE, MAT_WHITE, MAT_COPPER,
    MAT_COPPER, MAT_WHITE, MAT_WHITE, MAT_COPPER, MAT_WHITE
};

// ---------------------------------------------------------------------------
// THE RANDOMISER RANDOMISES RELATIONSHIPS, NOT COORDINATES.
//
// This subject is not a scatter of objects on a plane — it is ONE interlocking cluster of glass
// with mass and plates trapped inside it. Drawing fresh coordinates for each record (the way a
// scatter-based plan legitimately does) destroys exactly the three relationships that make it
// this object: volumes stop interlocking, bubbles float in open air, and plates detach into
// space. Every seed then reads as debris, no matter how well stratified the draw is.
//
// So each family is randomised against what it actually depends on:
//
//   slabs       attach to a PARENT volume, at an offset guaranteed to share solid volume
//   inclusions  are hosted INSIDE a slab, in groups, sized from that slab's own extent
//   plates      are hosted INSIDE a slab, sized from that slab's face
//
// The parent tree is transcribed from the reference, so `variation` can lerp each child's
// attach offset from "exactly where the reference put it" to a free draw and stay continuous
// and valid the whole way. This is the same principle as deriving a magnitude from an upstream
// record rather than from a parallel parameter — here the upstream record is the parent volume.
// ---------------------------------------------------------------------------

// Which volume each one hangs off. -1 is the root. A parent's index is always LOWER than its
// child's, so one sequential pass resolves the whole tree.
static const int SLAB_PARENT[12] = { -1, 0, 1, 2, 3, 4, 3, 3, 1, 0, 2, 6 };

// A fresh attach offset that is guaranteed to share volume with the parent.
//
// The attach axis comes from the CHILD'S OWN PROPORTION: a bar attaches end-on along x, a
// column along y. That single rule is most of why a random cluster still reads as architecture
// rather than as a pile — long things reach out, tall things stack.
float3 attachOffset(float3 ph, float3 ch, float rs)
{
    bool alongX = (ch.x > ch.y);
    if (vc_rnd(rs, 61.0) < 0.28) alongX = !alongX;          // some variety, not a rule
    float sgn = (vc_rnd(rs, 62.0) < 0.5) ? -1.0 : 1.0;
    // k < 1 is the whole guarantee: the centres sit closer than the sum of the half-extents,
    // so the boxes always share solid volume.
    float k = lerp(0.38, 0.80, vc_rnd(rs, 63.0));
    float dep = (vc_rnd(rs, 65.0) - 0.5) * 2.0 * max(ph.z - ch.z * 0.5, 0.03);

    if (alongX)
    {
        float lat = (vc_rnd(rs, 64.0) - 0.5) * 2.0 * max(ph.y - ch.y * 0.35, 0.02);
        return float3(sgn * (ph.x + ch.x) * k, lat, dep);
    }
    float lat = (vc_rnd(rs, 64.0) - 0.5) * 2.0 * max(ph.x - ch.x * 0.35, 0.02);
    return float3(lat, sgn * (ph.y + ch.y) * k, dep);
}

// Force a child to interlock with its parent, whatever the offset it arrived with.
//
// Two failure modes, two clamps. Clamped OUT, the boxes drift apart and the cluster falls into
// pieces — so every axis is capped below the touching distance. Clamped IN, a small child sits
// concentric inside a large parent and simply disappears — so the dominant axis is also pushed
// out to a minimum. Between the two, every draw is a cluster and every element is visible.
float3 enforceInterlock(float3 pp, float3 ph, float3 cp, float3 ch)
{
    float3 sum = ph + ch;
    float3 d = clamp(cp - pp, -sum * 0.88, sum * 0.88);

    float3 ad = abs(d);
    if (ad.x >= ad.y && ad.x >= ad.z)
    {
        float m = sum.x * 0.34;
        if (ad.x < m) d.x = (d.x < 0.0) ? -m : m;
    }
    else if (ad.y >= ad.z)
    {
        float m = sum.y * 0.34;
        if (ad.y < m) d.y = (d.y < 0.0) ? -m : m;
    }
    else
    {
        float m = sum.z * 0.34;
        if (ad.z < m) d.z = (d.z < 0.0) ? -m : m;
    }
    return pp + d;
}

// ---------------------------------------------------------------------------
// Arrangement presets. Each is a structural placement strategy applied on top of the
// transcribed tables, so materials, proportion families and depth survive a preset change.
// `axisSwap` lets a preset stand a bar on its end without the caller knowing what a bar is.
// ---------------------------------------------------------------------------
// Takes the record's half-extent and returns BOTH the placement and the extent, because a
// placement strategy that cannot resize is not a placement strategy: standing a 2.4-long bar
// on end in a rank of eight columns needs the width to come from the RANK'S PITCH, not from
// whatever the bar happened to be, or every column fuses into its neighbours and the preset
// renders as one continuous wall. The multiplier-only version could not express that.
float3 applyArrangement(float3 p, float3 hlf, uint slot, float s, out float3 outHalf)
{
    int pre = (int)arrangement;
    float3 halfMul = float3(1.0, 1.0, 1.0);
    bool axisSwap = false;
    outHalf = hlf;
    float3 res;

    if (pre == 2)
    {
        // Colonnade — a rank of eight columns across the frame. REPAIRED: the column width is
        // derived from the rank's pitch so instances can never touch (half-width plus bevel
        // must clear half the pitch), and the height comes from the record's own footprint so
        // the size hierarchy of the original cast survives being stood on end.
        uint local = slot % 8u;
        float pitch = 2.50 / 8.0;
        float t = ((float)local + 0.5) / 8.0;
        float x = lerp(-1.25, 1.25, t);
        // panels take a half-pitch offset so they interleave with the glass instead of
        // hiding exactly inside it
        float bias = (slot >= 24u) ? pitch * 0.5 : 0.0;
        float hx = pitch * 0.34;
        float hy = clamp(sqrt(max(hlf.x * hlf.y, 1e-4)) * 1.90, 0.16, 0.92);
        outHalf = float3(hx, hy, clamp(hlf.z, 0.12, 0.32)) * scale_master;
        float y = (vc_rnd(s + (float)slot, 7.0) - 0.5) * 0.42;
        return float3(x + bias, y, p.z * 1.4);
    }
    if (pre == 3)
    {
        // Cascade — a descending diagonal, scale ramping so the stack recedes to lower right.
        // REPAIRED: the original threw the long bars clean off both edges, because a 2.4-unit
        // bar centred near the end of the diagonal reaches past 2.1. Capping the LONGEST axis
        // and scaling the other two by the same ratio keeps every proportion intact while
        // guaranteeing the element fits its station.
        uint local = slot % 8u;
        float t = ((float)local + vc_rnd(s + (float)slot, 11.0) * 0.4) / 8.0;
        float3 g = lerp(float3(-1.22, 0.72, -0.30), float3(1.22, -0.72, 0.30), t);
        float k = lerp(1.22, 0.62, t);
        float3 h = hlf * k * scale_master;
        float longest = max(h.x, max(h.y, h.z));
        if (longest > 0.62) h *= 0.62 / longest;
        outHalf = h;
        return g;
    }

    if (pre == 1)
    {
        // Pinwheel — the cross broken into rotational symmetry. Each element is carried a
        // quarter turn around the centre by its slot, and every other one is stood on end,
        // so the bars still interlock but chase each other instead of crossing.
        float turn = ((float)(slot & 3u)) * 1.5707963;
        float ca = cos(turn), sa = sin(turn);
        // stage y is half the extent of stage x; normalise before rotating or the pinwheel
        // comes out as an ellipse that only reads at two of its four stations
        float2 q = float2(p.x, p.y * 1.5);
        q = float2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
        axisSwap = ((slot & 1u) == 1u);
        halfMul = float3(0.92, 0.92, 1.0);
        res = float3(q.x, q.y / 1.5, p.z) + float3(0.0, 0.0, (vc_rnd(s + (float)slot, 3.0) - 0.5) * 0.2);
    }
    else
    {
        // 0 Cross — the transcribed reference, breathed in or out from the centre.
        float2 j = (vc_hash22(float2(s * 5.7 + (float)slot * 3.3, 2.9)) - 0.5) * 2.0 * jitter;
        res = float3(p.xy * spread + j, p.z * depth_spread);
    }

    float3 h = hlf * halfMul * scale_master;
    outHalf = axisSwap ? float3(h.y, h.x, h.z) : h;
    return res;
}

// Keep an element's whole footprint inside a generous stage bound. Clamping the CENTRE is not
// enough: a long bar centred just inside the limit still hangs half its length outside the
// picture, which is exactly how the Cascade and Colonnade presets first failed. Clamping the
// centre against the element's own half-extent is what makes an arrangement preset safe for
// any cast the user builds.
float3 frameGuard(float3 pos, float3 half)
{
    float2 lim = float2(1.78, 1.24) - half.xy;
    lim = max(lim, float2(0.02, 0.02));
    return float3(clamp(pos.x, -lim.x, lim.x), clamp(pos.y, -lim.y, lim.y), clamp(pos.z, -0.85, 0.85));
}

// Stratified placement for the randomiser: a uniform draw reliably piles three records in one
// corner and leaves a third of the frame bare. Each record gets its own cell of a 6x4 grid and
// jitters INSIDE it, so a random seed still reads as a composition. The grid is 6 wide because
// the frame is 3:2 and square cells keep the draw isotropic.
// `stride` must be coprime with 24 so the permutation is a bijection over the cells.
float3 stratified(uint slot, uint stride, float s, float rs)
{
    uint cell = (slot * stride + (uint)(vc_rnd(s, 77.0) * 24.0)) % 24u;
    float cx = (float)(cell % 6u);
    float cy = (float)(cell / 6u);
    float2 jit = float2(vc_rnd(rs, 41.0), vc_rnd(rs, 42.0));
    float2 g = float2((cx + 0.15 + 0.70 * jit.x) / 6.0, (cy + 0.15 + 0.70 * jit.y) / 4.0);
    return float3((g.x - 0.5) * 2.9, (g.y - 0.5) * 1.9, (vc_rnd(rs, 43.0) - 0.5) * 0.6);
}

void buildSlabs(float s)
{
    uint want = (uint)clamp((float)slab_count, 0.0, 12.0);
    float v = saturate(variation);
    for (uint i = 0u; i < VC_SLABS; i++)
    {
        VcRec r = (VcRec)0;
        // A randomisation stream separate from r.seed, so re-rolling ONE record does not
        // shift what every other record drew.
        float rs = s * 11.7 + (float)i * 29.3 + 101.0;

        // PROPORTION is never drawn flat. The table encodes the composition's hierarchy — two
        // long bars, three columns, three blocks — and a uniform extent draw destroys that
        // hierarchy and reads as rubble. Randomising the MAGNITUDE around each slot's rank
        // keeps a random cluster composed.
        float3 rndHalf = SLAB_HALF[i] * float3(lerp(0.72, 1.40, vc_rnd(rs, 3.0)),
                                               lerp(0.75, 1.35, vc_rnd(rs, 4.0)),
                                               lerp(0.95, 1.45, vc_rnd(rs, 5.0)));
        // TEMPER THE ASPECT under variation. The reference's two bars are extremely slender
        // (2.4 long by 0.28 deep) and they read only because the transcribed arrangement packs
        // other volumes across them. A random cluster does not, so slivers just look like wire.
        // Pulling extremes 30% toward the record's own mean keeps a bar a bar while giving it
        // enough body to read as glass.
        float meanH = (rndHalf.x + rndHalf.y + rndHalf.z) / 3.0;
        rndHalf = lerp(rndHalf, float3(meanH, meanH, meanH), 0.30);
        float3 hlf = lerp(SLAB_HALF[i], rndHalf, v);
        float mat = (vc_rnd(rs, 7.0) < v * 0.55)
                    ? ((vc_rnd(rs, 8.0) < 0.72) ? (float)MAT_CLEAR
                                                : ((vc_rnd(rs, 9.0) < 0.5) ? (float)MAT_AMBER : (float)MAT_SMOKE))
                    : SLAB_MAT[i];

        // --- grow the cluster along the transcribed parent tree
        int par = SLAB_PARENT[i];
        if (v > 0.001 && i > 0u)
        {
            // Redraw the parent under variation, biased HARD toward the earliest volumes.
            // The transcribed tree is a chain (0->1->2->3->4->5), and following a chain with
            // random attach directions grows a straggling procession that wanders off frame.
            // Biasing the draw toward the root builds a bush instead — every element stays
            // near the middle of the mass, which is what makes an arbitrary seed read as one
            // sculpture rather than as a queue.
            uint cand = (uint)(pow(vc_rnd(rs, 66.0), 1.7) * (float)i);
            par = (int)min(cand, i - 1u);
        }

        float3 pos;
        if (par < 0)
        {
            // Under variation the root starts at the origin so growth is balanced about the
            // centre rather than trailing out from wherever the reference's first cube sat.
            pos = lerp(SLAB_POS[i], float3(0.0, 0.0, 0.0), v) * spread;
        }
        else
        {
            VcRec pr = Plan[VC_SLAB_0 + (uint)par];
            // When the parent was redrawn the reference offset no longer describes a real
            // relationship, so it only survives while the original tree does.
            float3 refOff = (par == SLAB_PARENT[i]) ? (SLAB_POS[i] - SLAB_POS[par])
                                                    : attachOffset(pr.dims, hlf, rs + 3.7);
            float3 rndOff = attachOffset(pr.dims, hlf, rs);
            // `spread` scales the OFFSET, not the absolute position, so the whole cluster
            // breathes without any child losing contact with its parent.
            pos = pr.pos + lerp(refOff, rndOff, v) * spread;
            // Only correct a DRAWN arrangement. The transcription already interlocks by
            // construction, and running the minimum-separation clamp over it nudged records
            // off their transcribed coordinates — variation 0 has to be the reference exactly.
            if (v > 0.001) pos = enforceInterlock(pr.pos, pr.dims, pos, hlf);
        }

        float3 h;
        float3 ap = applyArrangement(pos, hlf, i, s, h);
        h = max(h, 0.02);
        // Presets 1-3 place by their own strategy; only Cross grows a cluster, so only Cross
        // re-asserts interlock after the arrangement has had its say.
        if ((int)arrangement == 0 && par >= 0 && v > 0.001)
        {
            VcRec pr2 = Plan[VC_SLAB_0 + (uint)par];
            ap = enforceInterlock(pr2.pos, pr2.dims, ap, h);
        }

        r.pos = frameGuard(ap, h);
        r.dims = h;
        r.role = ROLE_SLAB;
        r.mat = mat;
        r.tint = float3(1.0, 1.0, 1.0);
        r.seed = s * 3.3 + (float)i * 17.0 + 1.0;
        r.p0 = edge_bevel;
        r.p1 = 0.0;
        r.flags = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[VC_SLAB_0 + i] = r;
    }
}

// Recentre the grown cluster and zoom it to fit the picture.
//
// This is the composition-level guarantee, and it is the counterpart to the relaxation pass a
// scatter-based plan needs. Growth by attachment produces a valid CLUSTER but says nothing
// about where that cluster ends up or how big it is — a few outward draws in the same direction
// and half the sculpture is outside the frame, which is the single most common way a random
// seed looks broken. Measuring the result and applying one uniform similarity transform makes
// every seed framed by construction, and because it is uniform, no proportion changes.
//
// Runs BEFORE the inclusions and plates are built, so they host off corrected volumes and
// inherit the framing for free.
void fitCluster()
{
    if (variation <= 0.001) return;   // variation 0 must remain exactly the transcription

    uint want = (uint)clamp((float)slab_count, 0.0, 12.0);
    if (want == 0u) return;

    float3 lo = float3(1e9, 1e9, 1e9);
    float3 hi = float3(-1e9, -1e9, -1e9);
    for (uint i = 0u; i < VC_SLABS; i++)
    {
        if (i < want)
        {
            VcRec r = Plan[VC_SLAB_0 + i];
            lo = min(lo, r.pos - r.dims);
            hi = max(hi, r.pos + r.dims);
        }
    }

    float3 c = (lo + hi) * 0.5;
    float3 ext = max((hi - lo) * 0.5, 1e-3);
    // A little inside the visible 1.68 x 1.12 half-frame, so the mass that bulges out of the
    // glass still has somewhere to go.
    float k = min(1.0, min(1.52 / ext.x, 1.00 / ext.y));

    for (uint j = 0u; j < VC_SLABS; j++)
    {
        VcRec r = Plan[VC_SLAB_0 + j];
        r.pos = (r.pos - c) * k;
        r.dims *= k;                  // uniform: a zoom, never a squash
        Plan[VC_SLAB_0 + j] = r;
    }
}

void buildInclusions(float s)
{
    uint want = (uint)clamp((float)inclusion_count, 0.0, 24.0);
    float v = saturate(variation);
    int form = (int)inclusion_form;

    for (uint i = 0u; i < VC_INCS; i++)
    {
        VcRec r = (VcRec)0;
        float rs = s * 13.1 + (float)i * 37.7 + 211.0;

        float3 base = INC_POS[i];
        float3 rad = INC_RAD[i];

        // The inclusion FORM is where the organic mass sits relative to the glass. This is a
        // structural axis, not a style one: it changes which volumes the light has to travel
        // through, so the whole image reorganises.
        if (form == 1)
        {
            // Spill — the mass drains to the bottom of the composition and hangs out of it
            base = float3(base.x * 0.86, base.y * 0.42 - 0.44, base.z);
            rad *= float3(1.12, 0.92, 1.06);
        }
        else if (form == 2)
        {
            // Column — the mass stacks into a single vertical core through the middle
            float t = ((float)i + 0.5) / 24.0;
            base = float3((vc_rnd(rs, 21.0) - 0.5) * 0.62 - 0.18,
                          lerp(0.94, -0.90, t),
                          (vc_rnd(rs, 22.0) - 0.5) * 0.40);
            rad *= 0.94;
        }
        else if (form == 3)
        {
            // Scatter — one bubble per slab neighbourhood, spread over the whole cross
            base = stratified(i, 11u, s, rs) * float3(0.92, 0.86, 0.7);
            rad *= lerp(0.80, 1.25, vc_rnd(rs, 23.0));
        }

        // --- host the mass INSIDE a glass volume rather than scattering it.
        //
        // This is the difference between a sculpture and a bubble bath. Scattered inclusions
        // float in open air where there is no glass to lens them, which loses the one idea the
        // whole image rests on. Records are taken in GROUPS of four sharing a host, so the mass
        // still fuses into lobed clusters instead of dispersing into confetti, and the radius
        // comes from the host's own smallest half-extent so a bubble is always in scale with
        // the volume containing it.
        uint wantSlabs = max((uint)clamp((float)slab_count, 1.0, 12.0), 1u);
        uint grp = i / 4u;
        uint host = (uint)(vc_rnd(s + (float)grp * 13.7, 71.0) * (float)wantSlabs) % wantSlabs;
        VcRec hs = Plan[VC_SLAB_0 + host];
        // Sizing off the host's SMALLEST half-extent alone makes every bubble in a slender bar
        // a pinhead. Blending toward the host's mean extent lets the mass fill its volume and
        // bulge out of it, which is what the reference actually does.
        float hostMin = min(hs.dims.x, min(hs.dims.y, hs.dims.z));
        float hostMean = (hs.dims.x + hs.dims.y + hs.dims.z) / 3.0;
        float hostScale = lerp(hostMin, hostMean, 0.45);

        // the group's own centre inside that volume, then each member around it
        float3 gc = hs.pos + (vc_hash33(float3((float)grp * 3.1 + s, 7.7, 2.3)) - 0.5) * hs.dims * 1.05;
        float3 rndPos = gc + (vc_hash33(float3(rs, 5.1, 9.4)) - 0.5) * hostScale * 1.9;
        // Capped below 1.0 of the host scale on purpose. Above that the mass swallows the
        // glass and the plates entirely, and the picture stops being glass-with-mass-inside
        // and becomes foam with some panels lost in it.
        float3 rndRad = float3(1.0, 0.92, 0.88) * hostScale * lerp(0.44, 0.90, vc_rnd(rs, 6.0));

        float3 pos = lerp(base, rndPos, v);
        float3 rr = lerp(rad, rndRad, v);

        // spread already moved the volumes; the mass rides its host rather than being scaled
        // about the origin a second time
        r.pos = lerp(pos * float3(spread, spread, depth_spread), pos, v);
        r.dims = max(rr * inclusion_scale * scale_master, 0.02);
        r.role = ROLE_INC;
        // Cavities are the reference's default reading; a few dense fluid pockets give the
        // mass internal structure instead of one uniform bubble field.
        r.mat = (vc_rnd(rs, 12.0) < fluid_mix) ? (float)MAT_FLUID : (float)MAT_CAVITY;
        r.tint = float3(1.0, 1.0, 1.0);
        r.seed = s * 7.1 + (float)i * 23.0 + 5.0;
        r.p0 = inclusion_fuse;
        r.p1 = inclusion_wobble * lerp(0.7, 1.3, vc_rnd(rs, 14.0));
        r.flags = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[VC_INC_0 + i] = r;
    }
}

void buildPanels(float s)
{
    uint want = (uint)clamp((float)panel_count, 0.0, 10.0);
    float v = saturate(variation);
    for (uint i = 0u; i < VC_PANELS; i++)
    {
        VcRec r = (VcRec)0;
        float rs = s * 17.3 + (float)i * 41.9 + 331.0;

        // --- host the plate INSIDE a glass volume, and size it from that volume's FACE.
        //
        // The plates only read as the reference's hard graphic rectangles because they are seen
        // THROUGH glass. Scattered into open air they become floating stickers, and the black
        // ones vanish against the backdrop entirely. Taking the extent from the host's face is
        // also what keeps a plate proportioned to the volume it sits in instead of needing a
        // second size parameter kept in agreement by hand.
        uint wantSlabs = max((uint)clamp((float)slab_count, 1.0, 12.0), 1u);
        uint host = (uint)(vc_rnd(s + (float)i * 7.3, 73.0) * (float)wantSlabs) % wantSlabs;
        VcRec hs = Plan[VC_SLAB_0 + host];

        float3 rndHalf = float3(hs.dims.x * lerp(0.34, 0.86, vc_rnd(rs, 15.0)),
                                hs.dims.y * lerp(0.34, 0.86, vc_rnd(rs, 16.0)),
                                PANEL_HALF[i].z);
        float3 rndPos = hs.pos + float3((vc_rnd(rs, 24.0) - 0.5) * hs.dims.x * 0.7,
                                        (vc_rnd(rs, 25.0) - 0.5) * hs.dims.y * 0.7,
                                        (vc_rnd(rs, 26.0) - 0.5) * hs.dims.z * 1.5);

        float3 pos = lerp(PANEL_POS[i], rndPos, v);
        float3 hlf = lerp(PANEL_HALF[i], rndHalf, v);
        float mat = (vc_rnd(rs, 17.0) < v * 0.6)
                    ? min(floor(lerp((float)MAT_WHITE, (float)MAT_COUNT, vc_rnd(rs, 18.0))), (float)(MAT_COUNT - 1))
                    : PANEL_MAT[i];

        float3 h;
        float3 ap = applyArrangement(pos, hlf, i + 24u, s, h);
        // A panel is a PLATE. Whatever an arrangement does to its face, its thickness is the
        // one dimension that must survive, or the graphic rectangles become slabs.
        h = max(float3(h.xy, hlf.z), 0.008);

        r.pos = frameGuard(ap, h);
        r.dims = h;
        r.role = ROLE_PANEL;
        r.mat = mat;
        r.tint = float3(1.0, 1.0, 1.0);
        r.seed = s * 2.7 + (float)i * 13.37 + 3.0;
        r.p0 = 0.0;
        r.p1 = 0.0;
        r.flags = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[VC_PANEL_0 + i] = r;
    }
}

// Nearest pickable record under a stage-space point, in the SAME space the canvas draws in.
// Smallest hit wins so a small inclusion resting on a long bar stays reachable.
uint pickRecord(float2 p)
{
    uint best = 0u;
    float bestScore = 1e9;

    // inclusions first: they sit visually on top of the glass in the schematic
    for (uint i = 0u; i < VC_INCS; i++)
    {
        VcRec r = Plan[VC_INC_0 + i];
        float d = length((p - r.pos.xy) / max(r.dims.xy, 0.02));
        float score = d * (r.dims.x * r.dims.y);
        if (r.active > 0.5 && d < 1.0 && score < bestScore) { bestScore = score; best = VC_INC_0 + i + 1u; }
    }
    if (best != 0u) return best;

    for (uint j = 0u; j < VC_PANELS; j++)
    {
        VcRec r = Plan[VC_PANEL_0 + j];
        float2 q = abs(p - r.pos.xy) - r.dims.xy;
        float area = r.dims.x * r.dims.y;
        if (r.active > 0.5 && max(q.x, q.y) < 0.0 && area < bestScore) { bestScore = area; best = VC_PANEL_0 + j + 1u; }
    }
    if (best != 0u) return best;

    for (uint k = 0u; k < VC_SLABS; k++)
    {
        VcRec r = Plan[VC_SLAB_0 + k];
        float2 q = abs(p - r.pos.xy) - r.dims.xy;
        float area = r.dims.x * r.dims.y;
        if (r.active > 0.5 && max(q.x, q.y) < 0.0 && area < bestScore) { bestScore = area; best = VC_SLAB_0 + k + 1u; }
    }
    return best;
}

// Normalised pointer uv -> stage space, through the SHARED conversion the canvas draws with.
// One definition, so the hit test and the picture cannot disagree.
float2 pointerToStage(float2 uv)
{
    return vc_uvToStage(uv);
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    VcRec hdr = Plan[VC_HEADER];
    float initFlag = hdr.tint.x;
    float salt     = hdr.seed;
    float sel      = hdr.pos.y;      // selected index + 1, 0 = nothing
    float dragOn   = hdr.dims.x;
    float2 grab    = float2(hdr.dims.y, hdr.dims.z);

    uint n = min((uint)_ViewportEventCount, 64u);

    // --- pass 1: keys. R changes the salt, so it has to land BEFORE the signature test or
    // the rebuild it asks for is overwritten by the next cook's unchanged signature.
    for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];
        if (ev.type == 4u && ev.phase == 1u)
        {
            uint c = (uint)ev.code;
            if (c == 18u) salt += 1.0;                               // R  reseed layout
            else if (c == 3u) sel = 0.0;                             // C  clear selection
            else if (sel > 0.5)
            {
                uint idx = (uint)(sel - 1.0);
                VcRec r = Plan[idx];
                uint fl = (uint)r.flags;
                bool touched = true;

                if (c == 13u)                                        // M  cycle material
                {
                    // Per-role material lists. Cycling a slab into "opaque black" would be a
                    // different object, not a different material, so each role stays inside
                    // the family that makes sense for it.
                    if (r.role == ROLE_SLAB)       r.mat = fmod(r.mat + 1.0, 3.0);                       // clear/amber/smoke
                    else if (r.role == ROLE_INC)   r.mat = (r.mat == (float)MAT_CAVITY) ? (float)MAT_FLUID : (float)MAT_CAVITY;
                    else                           r.mat = (float)MAT_WHITE + fmod(r.mat - (float)MAT_WHITE + 1.0, 3.0);
                }
                else if (c == 7u)                                    // G  grow
                    r.dims = min(r.dims * 1.12, 2.2);
                else if (c == 8u)                                    // H  shrink
                    r.dims = max(r.dims * 0.893, 0.012);
                else if (c == 26u)                                   // Z  push deeper
                    r.pos.z = max(r.pos.z - 0.06, -0.9);
                else if (c == 1u)                                    // A  pull nearer
                    r.pos.z = min(r.pos.z + 0.06, 0.9);
                else if (c == 24u)                                   // X  toggle on/off
                    r.active = (r.active > 0.5) ? 0.0 : 1.0;
                else if (c == 14u)                                   // N  re-roll this record
                {
                    r.seed += 7.77;
                    r.dims *= lerp(0.80, 1.25, vc_rnd(r.seed, 1.0));
                    r.p1 = inclusion_wobble * lerp(0.6, 1.5, vc_rnd(r.seed, 2.0));
                }
                else touched = false;

                if (touched) r.flags = (float)(fl | F_EDITED);
                Plan[idx] = r;
            }
        }
    }

    // Only STRUCTURAL parameters are in the signature. inclusion_wobble, tints, bevel and
    // every render-side control stay out, so they refresh in place without a rebuild.
    float sig = seed * 7.31
              + (float)arrangement * 137.7 + (float)inclusion_form * 53.3
              + (float)slab_count * 1.13 + (float)inclusion_count * 2.17 + (float)panel_count * 3.31
              + spread * 53.1 + scale_master * 97.3 + depth_spread * 31.7 + jitter * 61.3
              + inclusion_scale * 43.9 + fluid_mix * 29.7 + variation * 211.9
              + salt * 101.3 + PLAN_VERSION * 911.7;

    if (initFlag < 0.5 || abs(sig - hdr.pos.x) > 1e-4)
    {
        float s = seed + salt * 3.19;
        buildSlabs(s);
        fitCluster();
        buildInclusions(s);
        buildPanels(s);
        sel = 0.0;
        dragOn = 0.0;
    }

    // --- pass 2: pointer. Selection and drag share pickRecord() and stage space with the canvas.
    for (uint e2 = 0u; e2 < n; e2++)
    {
        ViewportEvent ev = _ViewportEvents[e2];
        if (ev.type == 5u)
        {
            float2 p = pointerToStage(ev.position);
            if (ev.code == 1u && ev.phase == 7u)
            {
                sel = (float)pickRecord(p);
            }
            else if (ev.code == 3u)
            {
                if (ev.phase == 5u)
                {
                    uint hit = pickRecord(p);
                    sel = (float)hit;
                    if (hit != 0u) { dragOn = 1.0; grab = Plan[hit - 1u].pos.xy - p; }
                }
                else if (ev.phase == 6u && dragOn > 0.5 && sel > 0.5)
                {
                    uint idx = (uint)(sel - 1.0);
                    VcRec r = Plan[idx];
                    r.pos.xy = clamp(p + grab, float2(-1.9, -1.4), float2(1.9, 1.4));
                    r.flags = (float)(((uint)r.flags) | F_EDITED);
                    Plan[idx] = r;
                }
                else { dragOn = 0.0; }
            }
        }
    }

    // --- appearance refresh. These must NOT be in the signature, so they are republished
    // every cook onto whatever records currently exist, hand-edited or not.
    for (uint a = 0u; a < VC_SLABS; a++)
    {
        VcRec r = Plan[VC_SLAB_0 + a];
        r.p0 = edge_bevel;
        int m = (int)r.mat;
        r.tint = (m == MAT_AMBER) ? amber_tint : ((m == MAT_SMOKE) ? float3(smoke_density, smoke_density, smoke_density)
                                                                   : float3(glass_clarity, glass_clarity, glass_clarity));
        Plan[VC_SLAB_0 + a] = r;
    }
    for (uint b = 0u; b < VC_INCS; b++)
    {
        VcRec r = Plan[VC_INC_0 + b];
        r.p0 = inclusion_fuse;
        // wobble amplitude is appearance; its per-record variation is structural and lives
        // in the seed, so a wobble tweak keeps every record's individual character
        r.p1 = inclusion_wobble * lerp(0.7, 1.3, vc_rnd(r.seed, 14.0));
        Plan[VC_INC_0 + b] = r;
    }
    for (uint c2 = 0u; c2 < VC_PANELS; c2++)
    {
        VcRec r = Plan[VC_PANEL_0 + c2];
        int m = (int)r.mat;
        r.tint = (m == MAT_COPPER) ? copper_tint : float3(plate_value, plate_value, plate_value);
        Plan[VC_PANEL_0 + c2] = r;
    }

    // selection is derived from the single stored index, never mirrored onto records
    for (uint i2 = 0u; i2 < VC_STAGE; i2++)
    {
        VcRec r = Plan[i2];
        uint f = (uint)r.flags;
        f = (sel > 0.5 && (uint)(sel - 1.0) == i2) ? (f | F_SELECTED) : (f & ~F_SELECTED);
        r.flags = (float)f;
        Plan[i2] = r;
    }

    uint liveS = 0u, liveI = 0u, liveP = 0u;
    for (uint c3 = 0u; c3 < VC_SLABS;  c3++) if (Plan[VC_SLAB_0  + c3].active > 0.5) liveS++;
    for (uint d3 = 0u; d3 < VC_INCS;   d3++) if (Plan[VC_INC_0   + d3].active > 0.5) liveI++;
    for (uint e3 = 0u; e3 < VC_PANELS; e3++) if (Plan[VC_PANEL_0 + e3].active > 0.5) liveP++;

    // Global stage state, published every cook so a rig tweak is live without a rebuild.
    VcRec st = (VcRec)0;
    // Orientation is a PLACEMENT decision, so it lives here. The backdrop deliberately does
    // NOT — it is lighting, and VC_Env is its single owner.
    st.pos = float3(assembly_yaw, assembly_pitch, 0.0);
    st.dims = float3(0.0, 0.0, 0.0);
    st.role = ROLE_HEADER;
    st.active = 1.0;
    Plan[VC_STAGE] = st;

    hdr.pos    = float3(sig, sel, 0.0);
    hdr.dims   = float3(dragOn, grab.x, grab.y);
    hdr.role   = ROLE_HEADER;
    hdr.mat    = 0.0;
    hdr.tint   = float3(1.0, (float)liveS, (float)liveI);
    hdr.seed   = salt;
    hdr.p0     = (float)liveP;
    hdr.p1     = 0.0;
    hdr.flags  = 0.0;
    hdr.active = 1.0;
    Plan[VC_HEADER] = hdr;
}
