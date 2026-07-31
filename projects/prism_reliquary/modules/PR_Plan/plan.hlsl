// PR_Plan / plan.hlsl — the plan authority for prism_reliquary.
//
// Single-threaded on purpose. 96 records is nothing next to a march pass, the layout is
// sequential, and keeping it on one thread means the slot ranges in relic.hlsli can be
// filled in a readable order.
//
// Every table below is a TRANSCRIPTION of the reference in image coordinates (x 0..1 left
// to right, y 0..1 top to bottom). The frame contract in relic.hlsli projects those to
// world at whatever depth the element is given. That is the whole point of the authority:
// there is exactly one place that answers "where is anything", and it answers in the same
// coordinates you can measure off the reference.

#include "../_shared/relic.hlsli"

RWStructuredBuffer<CastRec> Cast : register(u0);

// Bump whenever the GENERATION algorithm below changes. Parameters feed the rebuild
// signature; shader edits do not, so without this a recompile keeps serving the old plan.
#define PLAN_VERSION 1.0

// Image half-extent (fractions of frame width / height) -> world half-extents at depth z.
// World lengths are isotropic, so a vertical image fraction converts through the aspect.
float2 pr_wh(float2 h, float z)
{
    float w = pr_frame_w(z);
    return float2(h.x * w, h.y * w / PR_AR);
}

// The arrangement randomizer. `variation` blends the transcribed reference position (0)
// toward a bounded stratified re-roll (1). Sizes are never re-rolled, so the size hierarchy
// that makes the composition read survives every seed. variation = 0 is exactly the
// reference, so it can never be lost.
float2 pr_roll(float2 base, float k, float amount, float seed, float spread)
{
    float2 r = float2(pr_hash21(float2(k * 1.7, seed * 3.71 + 0.5)),
                      pr_hash21(float2(k * 2.3 + 11.3, seed * 5.13 + 2.5)));
    float2 alt = base + (r - 0.5) * float2(0.30, 0.24) * spread;
    alt = clamp(alt, float2(0.10, 0.07), float2(0.92, 0.88));
    return lerp(base, alt, saturate(amount));
}

// EXPLORATION AXIS: arrangement. `Reference` is the transcription. The other two are real
// alternative compositions assembled from the same records and the same hero anchor, not
// throwaway variants — each is a shipped preset the user keeps.
// The glyph is the only member that is architectural rather than a satellite: it is nearly
// the full height of the frame and it belongs behind the hero. Both alternate arrangements
// have to place it deliberately instead of feeding it through the satellite rule.
#define K_GLYPH 7.0

float2 pr_arrange(float2 base, float k, uint mode, float2 hero)
{
    if (mode == 0u) return base;

    bool   isGlyph = abs(k - K_GLYPH) < 0.5;
    float2 r;

    if (mode == 1u)
    {
        // Orbit — satellites ring the hero.
        // The radius is modest AND the result is clamped. An unclamped ring around a hero
        // that already sits right of centre throws its widest members clean off frame: the
        // first version of this preset put the whole gem lattice past the right edge.
        float a = PR_TAU * frac(k * 0.1910 + 0.13);
        float d = 0.20 + 0.07 * pr_hash11(k * 1.7);
        r = hero + float2(cos(a) * d * PR_AR, sin(a) * d);
        if (isGlyph) r = float2(hero.x - 0.115, 0.400);
    }
    else
    {
        // Colonnade — a left-hand vertical register, with the glyph standing full height
        // beside it rather than being crushed into the column with everything else.
        if (isGlyph) r = float2(0.335, 0.398);
        else
        {
            float t = frac(k * 0.1370 + 0.07);
            r = float2(0.215 + 0.150 * pr_hash11(k * 2.3), 0.150 + t * 0.640);
        }
    }

    // Frame guard. Every alternate arrangement stays inside the plate; a preset that
    // silently walks off the edge is a bug, not a variation.
    return clamp(r, float2(0.16, 0.14), float2(0.85, 0.82));
}

// ---------------------------------------------------------------------------
// Glyph bar emitter. Bars are axis-aligned rounded boxes; the "outline" read in the
// reference is a MATERIAL property (chromatic Fresnel on smoked glass), not geometry.
// ---------------------------------------------------------------------------
void emitBar(uint slot, float2 c, float2 h, float z, float sd)
{
    CastRec b = pr_blank();
    b.role   = ROLE_GLYPH;
    b.mat    = MAT_DGLASS;
    b.active = 1.0;
    b.pos    = pr_place(c, z);
    float2 wh = pr_wh(h, z);
    b.dims   = float3(wh.x, wh.y, pr_wlen(0.016, z));
    b.radius = pr_wlen(0.0035, z);
    b.rot    = float4(0, 0, 0, 1);
    b.tint   = PR_SMOKE;
    b.seed   = sd;
    Cast[slot] = b;
}

// ---------------------------------------------------------------------------
// Procedural generation of the whole composition. This is the "generate" half of
// generate-then-override: it runs only when the structural signature changes, never every
// cook, or hand edits would die instantly.
//
// It clears every semantic slot but leaves SLOT_EDIT alone — main() owns that record and
// rewrites it last.
// ---------------------------------------------------------------------------
void buildAll(float sd)
{
    [loop] for (uint c = 0u; c < (uint)SLOT_EDIT; c++) Cast[c] = pr_blank();

    float var = variation;
    float spr = spread;
    uint  arr = (uint)arrangement;

    // -----------------------------------------------------------------------
    // 0 — Stage. Owns the ground plane and the finish of the room. The renderer reads
    // these numbers rather than holding its own copy.
    // -----------------------------------------------------------------------
    CastRec st = pr_blank();
    st.role   = ROLE_STAGE;
    st.mat    = MAT_FLOOR;
    st.active = 1.0;
    st.pos    = float3(0.0, 0.0, 0.0);
    st.radius = 0.0;
    st.dims   = float3(floor_gloss, floor_ripple, backdrop_lift);
    st.tint   = PR_FLOORCOL;
    st.p0     = (float)arrangement;
    st.p1     = (float)glyph_style;
    st.seed   = sd;
    Cast[SLOT_STAGE] = st;

    // -----------------------------------------------------------------------
    // 1 — The hero. A fat torus (minor/major = 0.45) tipped so the opening faces up and
    // toward camera-left, which is what puts the thick near arc across the lower right.
    // -----------------------------------------------------------------------
    float  zT   = 0.0;
    float2 tImg = pr_roll(float2(0.605, 0.585), 1.0, var * 0.55, sd, spr);

    CastRec tr = pr_blank();
    tr.role   = ROLE_TORUS;
    tr.mat    = MAT_FUR;
    tr.active = 1.0;
    tr.pos    = pr_place(tImg, zT);
    tr.radius = pr_wlen(0.1825 * scale_master, zT);
    tr.dims   = float3(pr_wlen(0.0825 * scale_master, zT), fur_length, fur_curl);
    // Base flip puts the torus hole on +Z (facing camera); the euler term is the tip.
    tr.rot    = pr_qmul(pr_qeuler(float3(radians(torus_pitch), radians(torus_yaw), radians(torus_roll))),
                        pr_qaxis(float3(1, 0, 0), PR_PI * 0.5));
    tr.tint   = PR_PELT;
    tr.p0     = fur_density;
    tr.p1     = irid_gain;
    tr.seed   = sd + 3.0;
    Cast[SLOT_TORUS] = tr;

    // -----------------------------------------------------------------------
    // 2..11 — The glyph. EXPLORATION AXIS: glyph_style.
    // The reference is the Double Cross: a patriarchal cross plus a depth-offset ghost
    // copy, which is what produces the doubled outline through the whole figure.
    // -----------------------------------------------------------------------
    float  zG  = -0.90;
    float  zGh = -1.35;
    float2 gB  = pr_arrange(float2(0.480, 0.398), 7.0, arr, tImg);
    float2 gO  = pr_roll(gB, 7.0, var * 0.35, sd, spr) - float2(0.480, 0.398);
    uint   gs  = (uint)glyph_style;

    if (gs == 0u)
    {
        emitBar(SLOT_GLYPH + 0u, gO + float2(0.4800, 0.398), float2(0.0240, 0.3225), zG,  sd);
        emitBar(SLOT_GLYPH + 1u, gO + float2(0.5275, 0.185), float2(0.1325, 0.0190), zG,  sd + 1.0);
        emitBar(SLOT_GLYPH + 2u, gO + float2(0.4825, 0.302), float2(0.1225, 0.0190), zG,  sd + 2.0);
        emitBar(SLOT_GLYPH + 3u, gO + float2(0.4430, 0.372), float2(0.0205, 0.2900), zGh, sd + 3.0);
        emitBar(SLOT_GLYPH + 4u, gO + float2(0.4920, 0.160), float2(0.1180, 0.0165), zGh, sd + 4.0);
        emitBar(SLOT_GLYPH + 5u, gO + float2(0.4470, 0.277), float2(0.1080, 0.0165), zGh, sd + 5.0);
    }
    else if (gs == 1u)
    {
        emitBar(SLOT_GLYPH + 0u, gO + float2(0.4800, 0.398), float2(0.0260, 0.3225), zG, sd);
        emitBar(SLOT_GLYPH + 1u, gO + float2(0.4800, 0.232), float2(0.1420, 0.0205), zG, sd + 1.0);
    }
    else
    {
        // Lattice Tower — same vertical spine, four rungs stepping down in width.
        emitBar(SLOT_GLYPH + 0u, gO + float2(0.4550, 0.398), float2(0.0140, 0.3225), zG,  sd);
        emitBar(SLOT_GLYPH + 1u, gO + float2(0.5100, 0.398), float2(0.0140, 0.3225), zGh, sd + 1.0);
        [unroll] for (uint r = 0u; r < 4u; r++)
        {
            float ty = 0.115 + (float)r * 0.155;
            float tw = 0.0700 - (float)r * 0.0075;
            emitBar(SLOT_GLYPH + 2u + r, gO + float2(0.4825, ty), float2(tw, 0.0115), zG, sd + 6.0 + (float)r);
        }
    }

    // -----------------------------------------------------------------------
    // 12 — Gem backing plate, and 16.. the chips themselves.
    // The plate carries the whole lattice (half-extents + cols/rows) so the renderer can
    // index a cell from the sample position in O(1) instead of testing 40 chips per step.
    // -----------------------------------------------------------------------
    float  zP   = -1.60;
    float2 pImg = pr_roll(pr_arrange(float2(0.2350, 0.2475), 21.0, arr, tImg), 21.0, var * 0.45, sd, spr);
    float2 pH   = float2(0.0980, 0.1150);
    // cols * rows must fit GEM_MAX, because chips are addressed BY CELL, not compacted.
    uint   cols = (uint)clamp(gem_cols, 1, 8);
    uint   rows = (uint)clamp(gem_rows, 1, 8);
    while (cols * rows > (uint)GEM_MAX && rows > 1u) rows--;
    while (cols * rows > (uint)GEM_MAX && cols > 1u) cols--;

    CastRec pl = pr_blank();
    pl.role   = ROLE_PLATE;
    pl.mat    = MAT_PLATE;
    pl.active = 1.0;
    pl.pos    = pr_place(pImg, zP);
    float2 pw = pr_wh(pH, zP);
    pl.dims   = float3(pw.x, pw.y, pr_wlen(0.010, zP));
    pl.radius = pr_wlen(0.004, zP);
    pl.tint   = PR_VOID * 0.75;
    pl.p0     = (float)cols;
    pl.p1     = (float)rows;
    pl.seed   = sd;
    Cast[SLOT_PLATE] = pl;

    // Chips live at SLOT_GEM + (row * cols + col) — ADDRESSED BY CELL, never compacted.
    // Compaction would force the renderer to scan 40 records per march step to find the one
    // chip a sample point is near; cell addressing makes it a single indexed read. Empty
    // cells stay as inactive records, and the preview tally counts only the active ones.
    [loop] for (uint ry = 0u; ry < rows; ry++)
    {
        [loop] for (uint cx = 0u; cx < cols; cx++)
        {
            uint   gi    = ry * cols + cx;
            float2 cellN = ((float2((float)cx, (float)ry) + 0.5) / float2((float)cols, (float)rows) - 0.5) * 2.0;
            float  h0    = pr_hash21(float2((float)cx * 3.1 + 0.7, (float)ry * 5.9 + sd * 0.37));
            float  h1    = pr_hash21(float2((float)ry * 2.3 + 9.1, (float)cx * 7.7 + sd * 0.61));
            bool   occ   = (h0 <= gem_fill) && (gi < (uint)GEM_MAX);

            if (occ)
            {
                CastRec gm = pr_blank();
                gm.role   = ROLE_GEM;
                gm.mat    = MAT_GEM;
                gm.active = 1.0;
                gm.radius = min(pl.dims.x / (float)cols, pl.dims.y / (float)rows) * (0.28 + 0.20 * h1);
                // Derived from the plate, never from a parallel position parameter. The z
                // offset must CLEAR the slab's own half-depth — sitting a chip at a fraction
                // of dims.z buries it inside the plate, where it renders as nothing at all.
                gm.pos    = pl.pos + float3(cellN.x * pl.dims.x * 0.84,
                                           -cellN.y * pl.dims.y * 0.84,
                                            pl.dims.z + gm.radius * 0.30);
                gm.dims   = float3(gm.radius * (0.55 + 0.5 * h0), 0.0, 0.0);
                gm.rot    = pr_qeuler(float3(0.0, 0.0, (h1 - 0.5) * 1.4));
                // The reference's chips are mostly cold white with a run of ruby ones
                // clustered to the right of the lattice.
                // -cellN.x: plate-local +x points to screen LEFT after the handedness flip, and the
                // reference clusters its ruby chips to the RIGHT of the lattice.
                float ruby = step(0.42, -cellN.x * 0.5 + 0.5 + (h1 - 0.5) * 0.35);
                gm.tint   = lerp(PR_CHALK * 0.42, PR_RUBY * 0.85, ruby * gem_ruby);
                gm.p0     = floor(h1 * 3.0);          // 0 diamond, 1 square, 2 round
                gm.p1     = 0.35 + 0.65 * h0;         // glint strength
                gm.seed   = h0 * 97.0 + h1 * 13.0;
                Cast[SLOT_GEM + gi] = gm;
            }
        }
    }

    // -----------------------------------------------------------------------
    // 56..59 — Spheres. Two chrome, one marbled resting on the floor.
    // -----------------------------------------------------------------------
    float2 s0i = pr_roll(pr_arrange(float2(0.7550, 0.3500), 31.0, arr, tImg), 31.0, var * 0.5, sd, spr);
    CastRec s0 = pr_blank();
    s0.role = ROLE_SPHERE; s0.mat = MAT_CHROME; s0.active = 1.0;
    s0.pos    = pr_place(s0i, -0.15);
    s0.radius = pr_wlen(0.0650 * scale_master, -0.15);
    s0.tint   = PR_STEEL;
    s0.p0     = 0.02;     // roughness
    s0.aux.y  = s0.pos.y; // rest height for the float animation
    s0.seed   = sd + 11.0;
    Cast[SLOT_SPHERE + 0u] = s0;

    float2 s1i = pr_roll(pr_arrange(float2(0.6850, 0.2450), 37.0, arr, tImg), 37.0, var * 0.6, sd, spr);
    CastRec s1 = pr_blank();
    s1.role = ROLE_SPHERE; s1.mat = MAT_CHROME; s1.active = 1.0;
    s1.pos    = pr_place(s1i, -0.55);
    s1.radius = pr_wlen(0.0220 * scale_master, -0.55);
    s1.tint   = PR_STEEL;
    s1.p0     = 0.015;
    s1.aux.y  = s1.pos.y;
    s1.seed   = sd + 13.0;
    Cast[SLOT_SPHERE + 1u] = s1;

    // Marble: placed from the reference, then dropped so it actually touches the floor.
    float2 s2i = pr_roll(pr_arrange(float2(0.2650, 0.7900), 41.0, arr, tImg), 41.0, var * 0.45, sd, spr);
    CastRec s2 = pr_blank();
    s2.role = ROLE_SPHERE; s2.mat = MAT_MARBLE; s2.active = 1.0;
    s2.radius = pr_wlen(0.0550 * scale_master, 1.30);
    s2.pos    = pr_place(s2i, 1.30);
    s2.pos.y  = s2.radius;
    s2.flags  = F_FLOOR;          // dragging must not lift it off the ground
    s2.tint   = float3(0.66, 0.67, 0.70);
    s2.p0     = 0.06;
    s2.seed   = sd + 17.0;
    Cast[SLOT_SPHERE + 2u] = s2;

    // -----------------------------------------------------------------------
    // 60 — The light ring, lying flat on the floor under the hero.
    // -----------------------------------------------------------------------
    float2 rImg = pr_roll(pr_arrange(float2(0.7750, 0.8300), 51.0, arr, tImg), 51.0, var * 0.35, sd, spr);
    CastRec rg = pr_blank();
    rg.role = ROLE_RING; rg.mat = MAT_EMIT; rg.active = 1.0;
    rg.radius = pr_wlen(0.1150 * scale_master, 0.55);
    rg.dims   = float3(pr_wlen(0.0120 * scale_master, 0.55), 0.0, 0.0);
    rg.pos    = pr_place(rImg, 0.55);
    rg.pos.y  = rg.dims.x * 1.05;
    rg.flags  = F_FLOOR;
    rg.rot    = float4(0, 0, 0, 1);
    rg.tint   = PR_CHALK;
    rg.p0     = ring_glow;
    rg.seed   = sd + 19.0;
    Cast[SLOT_RING] = rg;

    // -----------------------------------------------------------------------
    // 61 — The soap membrane. A control record: centre, extent, billow depth and the
    // film thickness the interference model integrates.
    // -----------------------------------------------------------------------
    float2 fImg = pr_roll(pr_arrange(float2(0.2950, 0.5450), 61.0, arr, tImg), 61.0, var * 0.4, sd, spr);
    CastRec fm = pr_blank();
    fm.role = ROLE_FILM; fm.mat = MAT_FILM; fm.active = 1.0;
    fm.pos    = pr_place(fImg, 0.90);
    // Extent is the drape's BOUND, not its silhouette — the sheet inside it is a curved
    // billow, so the box is deliberately a little smaller than the reference's outline.
    float2 fh = pr_wh(float2(0.1650, 0.2000), 0.90);
    fm.dims   = float3(fh.x, fh.y, pr_wlen(0.1400, 0.90) * film_billow);
    fm.radius = pr_wlen(0.0030, 0.90);
    fm.rot    = pr_qeuler(float3(radians(-5.0), radians(10.0), radians(-4.0)));
    fm.tint   = float3(1.0, 1.0, 1.0);
    fm.p0     = film_thickness;
    fm.p1     = film_folds;
    fm.seed   = sd + 23.0;
    Cast[SLOT_FILM] = fm;

    // -----------------------------------------------------------------------
    // 62..63 — The support post running from the glyph down into the floor.
    // -----------------------------------------------------------------------
    float postTopY = pr_place(gO + float2(0.472, 0.720), zG).y;
    CastRec po = pr_blank();
    po.role = ROLE_POST; po.mat = MAT_DGLASS; po.active = 1.0;
    po.radius = pr_wlen(0.0055, zG);
    po.dims   = float3(po.radius, postTopY * 0.5, po.radius);
    po.pos    = float3(pr_place(gO + float2(0.472, 0.5), zG).x, postTopY * 0.5, zG);
    po.tint   = PR_SMOKE;
    po.seed   = sd + 29.0;
    Cast[SLOT_POST + 0u] = po;
}

// ===========================================================================
// EDITOR
//
// The plan authority is directly manipulable, not a read-only generator. Everything below
// is the "override" half of generate-then-override: pick a record, move it, change what it
// is made of, resize it, switch it off, re-roll it — and have all of that survive cooks,
// saves and undo.
//
// WHY THESE VERBS. The edit set is designed for this subject rather than inherited from
// another project. This reference is fundamentally about MATERIAL — the whole image is fur
// against chrome against smoked glass against cut stone — and about the SIZE HIERARCHY that
// makes the composition read. So material and discrete scale are the two things worth
// putting on keys, plus presence and per-record re-roll. Chips are the exception: a chip is
// too small for its size to register, but its CUT is exactly what you see, so K cycles the
// cut there instead.
//
// COORDINATE DISCIPLINE. The canvas is 4:5 and its uv IS reference-image space, and viewport
// pointer positions arrive in exactly that same normalized space. Pointer, pick and draw
// therefore share one coordinate system by construction. Records store WORLD positions, so a
// drag converts through pr_place/pr_unplace at the record's own depth — dragging slides a
// record across the image plane without changing how far away it is, which is the right
// editing semantic for a composition transcribed from a photograph.
// ===========================================================================

// q-space: image space with x scaled by aspect, so a circular hit test is actually circular.
// Identical to the space canvas.hlsl draws in — that is the point.
float2 ed_toQ(float3 world) { float2 im = pr_unplace(world); return float2(im.x * PR_AR, im.y); }
float  ed_qh(float w, float z) { return w / max(pr_frame_h(z), 1e-4); }

// Nearest pickable record under an image-space point, returned as slot + 1 (0 = nothing).
// SMALLEST HIT WINS, so a chip sitting on its backing plate stays reachable and a sphere
// resting against the torus does not get swallowed by it.
uint ed_pick(float2 imgP)
{
    float2 q = float2(imgP.x * PR_AR, imgP.y);
    uint  best = 0u;
    float bestScore = 1e9;

    [loop] for (uint i = 0u; i < (uint)SLOT_EDIT; i++)
    {
        CastRec r = Cast[i];
        if (r.role == ROLE_NONE || r.role == ROLE_STAGE) continue;

        float2 c = ed_toQ(r.pos);
        float  score = 1e9;

        if (r.role == ROLE_GLYPH || r.role == ROLE_PLATE || r.role == ROLE_POST || r.role == ROLE_FILM)
        {
            float2 h = float2(ed_qh(r.dims.x, r.pos.z), ed_qh(r.dims.y, r.pos.z)) + 0.004;
            float2 d = abs(q - c) - h;
            if (max(d.x, d.y) < 0.0) score = h.x * h.y;
        }
        else
        {
            // the torus picks on its full outer disc; everything else on its own radius
            float extra = (r.role == ROLE_TORUS) ? r.dims.x : 0.0;
            float rad = ed_qh(r.radius + extra, r.pos.z) + 0.004;
            if (length(q - c) < rad) score = rad * rad;
        }

        // A switched-off record stays pickable, just heavily penalised. Without this, X
        // would be a one-way trip: nothing could ever be turned back on.
        if (r.active < 0.5) score *= 24.0;

        if (score < bestScore) { bestScore = score; best = i + 1u; }
    }
    return best;
}

// K steps a record through three discrete sizes. Applied as a RATIO against the previous
// step rather than against a stored base, so it composes with the Properties sliders and
// cycling 0 -> 1 -> 2 -> 0 returns exactly to the original size.
float ed_kindScale(float k) { return (k < 0.5) ? 1.0 : ((k < 1.5) ? 0.72 : 1.38); }

// M cycles what a record is MADE OF, through a list that makes sense for its role.
float ed_cycleMat(float role, float mat)
{
    if (role == ROLE_TORUS)
    {
        if (mat == MAT_FUR)    return MAT_CHROME;
        if (mat == MAT_CHROME) return MAT_MARBLE;
        return MAT_FUR;
    }
    if (role == ROLE_SPHERE)
    {
        if (mat == MAT_CHROME) return MAT_MARBLE;
        if (mat == MAT_MARBLE) return MAT_DGLASS;
        if (mat == MAT_DGLASS) return MAT_GEM;
        return MAT_CHROME;
    }
    if (role == ROLE_GEM)
    {
        if (mat == MAT_GEM)    return MAT_CHROME;
        if (mat == MAT_CHROME) return MAT_EMIT;
        return MAT_GEM;
    }
    if (role == ROLE_GLYPH || role == ROLE_POST)
    {
        if (mat == MAT_DGLASS) return MAT_CHROME;
        if (mat == MAT_CHROME) return MAT_EMIT;
        return MAT_DGLASS;
    }
    if (role == ROLE_RING)  return (mat == MAT_EMIT)  ? MAT_CHROME : MAT_EMIT;
    if (role == ROLE_PLATE) return (mat == MAT_PLATE) ? MAT_DGLASS : MAT_PLATE;
    return mat;                      // the membrane has its own pass; leave it alone
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0) return;

    CastRec hdr = Cast[SLOT_EDIT];

    // HEADER VALIDITY GUARD. A persistent buffer outlives the schema that wrote it: reopen a
    // project saved before a record grew a field and the restore hands back the old bytes
    // reinterpreted at the new stride, which is garbage that looks like plausible floats.
    // Requiring both the role tag and the version stamp turns that into a clean rebuild
    // instead of a corrupted plan that is very hard to diagnose from the picture.
    bool headerOK = (hdr.role == ROLE_EDIT) && (abs(hdr.aux.x - PLAN_VERSION) < 1e-4);

    float  sig0 = headerOK ? hdr.pos.x    : -1.0;
    float  sel  = headerOK ? hdr.pos.y    : 0.0;   // selected slot + 1, 0 = nothing
    float  drag = headerOK ? hdr.pos.z    : 0.0;
    float2 grab = headerOK ? hdr.dims.xy  : float2(0, 0);
    float  salt = headerOK ? hdr.dims.z   : 0.0;
    float  init = headerOK ? hdr.radius   : 0.0;

    uint n = min((uint)_ViewportEventCount, 64u);

    // ---- pass 1: keys -----------------------------------------------------
    // Keys run BEFORE the signature test because R changes the salt, which feeds the
    // signature and must be able to trigger this cook's rebuild.
    [loop] for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];
        if (ev.type != 4u || ev.phase != 1u) continue;
        uint c = (uint)ev.code;

        if (c == 18u) { salt += 1.0; }                  // R  reseed the whole layout
        else if (c == 3u) { sel = 0.0; }                // C  clear selection
        else if (sel > 0.5)
        {
            uint idx = (uint)(sel - 1.0);
            CastRec r = Cast[idx];

            if (c == 11u)                               // K  cycle kind
            {
                if (r.role == ROLE_GEM)
                {
                    r.p0 = fmod(r.p0 + 1.0, 3.0);       // chips cycle CUT, not size
                }
                else
                {
                    float nk = fmod(r.aux.x + 1.0, 3.0);
                    float sc = ed_kindScale(nk) / ed_kindScale(r.aux.x);
                    r.aux.x = nk;

                    if (r.role == ROLE_TORUS)       r.dims.x *= sc;          // minor radius only
                    else if (r.role == ROLE_RING) { r.radius *= sc; r.dims.x *= sc; }
                    else if (r.role == ROLE_SPHERE) r.radius *= sc;
                    else                          { r.dims.xy *= sc; r.radius *= sc; }

                    // The lattice owns its chips: resizing the panel has to carry every
                    // chip the user has not hand-placed, or panel and contents silently
                    // disagree.
                    if (r.role == ROLE_PLATE)
                    {
                        [loop] for (uint g = 0u; g < (uint)GEM_MAX; g++)
                        {
                            CastRec gm = Cast[SLOT_GEM + g];
                            if (gm.role != ROLE_GEM || pr_hasFlag(gm, F_EDITED)) continue;
                            gm.pos.xy = r.pos.xy + (gm.pos.xy - r.pos.xy) * sc;
                            gm.radius *= sc;
                            Cast[SLOT_GEM + g] = gm;
                        }
                    }
                }
                r.flags = pr_setFlag(r.flags, F_EDITED, true);
            }
            else if (c == 13u)                          // M  cycle material
            {
                r.mat   = ed_cycleMat(r.role, r.mat);
                r.flags = pr_setFlag(r.flags, F_EDITED, true);
            }
            else if (c == 24u)                          // X  toggle on/off
            {
                r.active = (r.active > 0.5) ? 0.0 : 1.0;
                r.flags  = pr_setFlag(r.flags, F_EDITED, true);
            }
            else if (c == 14u)                          // N  re-roll this record
            {
                r.seed += 7.77;
                float h0 = pr_hash11(r.seed * 1.7);
                float h1 = pr_hash11(r.seed * 2.9 + 4.1);
                if (r.role == ROLE_GEM)
                {
                    r.p0   = floor(h1 * 3.0);
                    r.p1   = 0.35 + 0.65 * h0;
                    r.tint = lerp(PR_CHALK * 0.42, PR_RUBY * 0.85, step(0.5, h0) * gem_ruby);
                }
                r.flags = pr_setFlag(r.flags, F_EDITED, true);
            }
            Cast[idx] = r;
        }
    }

    // ---- signature -------------------------------------------------------
    // ONLY structural parameters belong here — the ones that change which records exist or
    // where they sit. Appearance parameters are refreshed in place further down, so that
    // nudging a colour or a glow does not throw away the user's layout work.
    float sig = (float)arrangement * 37.70 + (float)glyph_style * 13.30
              + variation * 137.90 + seed * 7.31 + spread * 53.10 + scale_master * 97.30
              + (float)gem_cols * 1.13 + (float)gem_rows * 2.17
              + gem_fill * 31.70 + gem_ruby * 61.30
              + salt * 101.30 + PLAN_VERSION * 911.70;

    if (init < 0.5 || abs(sig - sig0) > 1e-4)
    {
        buildAll(seed + salt * 3.19);
        sel = 0.0;
        drag = 0.0;
        init = 1.0;
    }

    // ---- pass 2: pointer --------------------------------------------------
    // ev.position is normalized preview space, which is this canvas's uv, which is
    // reference-image space. No remapping, and nothing to get out of step.
    [loop] for (uint e2 = 0u; e2 < n; e2++)
    {
        ViewportEvent ev = _ViewportEvents[e2];
        if (ev.type != 5u) continue;
        float2 p = ev.position;

        if (ev.code == 1u && ev.phase == 7u)            // completed click -> select
        {
            sel = (float)ed_pick(p);
        }
        else if (ev.code == 3u)                         // drag
        {
            if (ev.phase == 5u)                         // begin
            {
                uint hit = ed_pick(p);
                sel = (float)hit;
                drag = 0.0;
                if (hit != 0u)
                {
                    drag = 1.0;
                    grab = pr_unplace(Cast[hit - 1u].pos) - p;
                }
            }
            else if (ev.phase == 6u && drag > 0.5 && sel > 0.5)   // update
            {
                uint idx = (uint)(sel - 1.0);
                CastRec r = Cast[idx];

                float2 img = clamp(p + grab, float2(0.02, 0.02), float2(0.98, 0.98));
                float3 was = r.pos;
                r.pos = pr_place(img, r.pos.z);
                if (pr_hasFlag(r, F_FLOOR)) r.pos.y = was.y;      // stays on the ground
                r.aux.y = r.pos.y;                                // re-base the float
                r.flags = pr_setFlag(r.flags, F_EDITED, true);
                Cast[idx] = r;

                // Derived records follow their parent: moving the panel moves every chip
                // the user has not hand-placed.
                if (r.role == ROLE_PLATE)
                {
                    float3 d = r.pos - was;
                    [loop] for (uint g = 0u; g < (uint)GEM_MAX; g++)
                    {
                        CastRec gm = Cast[SLOT_GEM + g];
                        if (gm.role != ROLE_GEM || pr_hasFlag(gm, F_EDITED)) continue;
                        gm.pos += d;
                        Cast[SLOT_GEM + g] = gm;
                    }
                }
            }
            else { drag = 0.0; }                        // end / cancel
        }
    }

    // ---- appearance refresh ------------------------------------------------
    // Deliberately outside the signature: these fields change how the composition LOOKS,
    // not where anything is, so they update live without costing the user their edits.
    CastRec st = Cast[SLOT_STAGE];
    if (st.role == ROLE_STAGE)
    {
        st.dims = float3(floor_gloss, floor_ripple, backdrop_lift);
        st.p0   = (float)arrangement;
        st.p1   = (float)glyph_style;
        Cast[SLOT_STAGE] = st;
    }

    CastRec tr = Cast[SLOT_TORUS];
    if (tr.role == ROLE_TORUS)
    {
        tr.rot    = pr_qmul(pr_qeuler(float3(radians(torus_pitch), radians(torus_yaw), radians(torus_roll))),
                            pr_qaxis(float3(1, 0, 0), PR_PI * 0.5));
        tr.dims.y = fur_length;
        tr.dims.z = fur_curl;
        tr.p0     = fur_density;
        tr.p1     = irid_gain;
        Cast[SLOT_TORUS] = tr;
    }

    CastRec rg = Cast[SLOT_RING];
    if (rg.role == ROLE_RING) { rg.p0 = ring_glow; Cast[SLOT_RING] = rg; }

    CastRec fm = Cast[SLOT_FILM];
    if (fm.role == ROLE_FILM)
    {
        fm.dims.z = pr_wlen(0.1400, fm.pos.z) * film_billow;
        fm.p0     = film_thickness;
        fm.p1     = film_folds;
        Cast[SLOT_FILM] = fm;
    }

    // ---- clock -------------------------------------------------------------
    // PHASE IS INTEGRATED, never rate * _Time. Multiplying a live rate by absolute time
    // makes every speed change jump the animation; accumulating _DeltaTime * rate means the
    // slider changes the speed and nothing else. One clock for the whole show — consumers
    // scale it by their own rate — so nothing can drift out of step with anything else.
    float phase = headerOK ? hdr.aux.y : 0.0;
    phase += _DeltaTime * anim_rate;
    phase = fmod(phase, 100000.0);          // bounded, so float precision never degrades

    // ---- animation ----------------------------------------------------------
    // The plan owns placement, so placement-based motion belongs HERE, not in the renderer.
    // Everything below skips records the user has hand-edited: touching something is a
    // statement that you want it where you put it.

    // Chrome spheres breathe up and down around their rest height. The marble is F_FLOOR
    // and deliberately excluded — a sphere resting on the ground should stay on it.
    [loop] for (uint sp = 0u; sp < (uint)SPHERE_MAX; sp++)
    {
        CastRec r = Cast[SLOT_SPHERE + sp];
        if (r.role != ROLE_SPHERE || pr_hasFlag(r, F_FLOOR)) continue;
        if (r.aux.y == 0.0) r.aux.y = r.pos.y;          // first cook after an old rebuild
        r.pos.y = r.aux.y + sin(phase * 0.55 + (float)sp * 2.10) * sphere_float * r.radius;
        Cast[SLOT_SPHERE + sp] = r;
    }

    // The lattice rearranges PIECE BY PIECE rather than continuously: a discrete tick picks
    // one chip and re-cuts it. Continuous motion on 36 chips reads as shimmer; one chip
    // changing every few seconds reads as a mechanism.
    float tick = floor(phase * lattice_rate);
    if (headerOK && tick != hdr.aux.z && lattice_rate > 0.0)
    {
        CastRec lat  = Cast[SLOT_PLATE];
        uint    span = (uint)clamp(lat.p0 * lat.p1, 1.0, (float)GEM_MAX);
        uint  gi   = (uint)(pr_hash11(tick * 1.37 + 0.5) * (float)span) % max(span, 1u);
        CastRec gm = Cast[SLOT_GEM + gi];
        if (gm.role == ROLE_GEM && !pr_hasFlag(gm, F_EDITED))
        {
            float h1 = pr_hash11(tick * 5.11 + (float)gi * 0.77);
            gm.p0 = fmod(gm.p0 + 1.0 + floor(h1 * 2.0), 3.0);
            gm.p1 = 0.35 + 0.65 * pr_hash11(tick * 9.13 + (float)gi);
            Cast[SLOT_GEM + gi] = gm;
        }
    }

    // Publish the clock on the stage record so the renderer can drive shading motion from
    // the same phase the layout is using.
    st = Cast[SLOT_STAGE];
    if (st.role == ROLE_STAGE) { st.aux.x = phase; Cast[SLOT_STAGE] = st; }

    // ---- editor header -----------------------------------------------------
    hdr = pr_blank();
    hdr.role   = ROLE_EDIT;
    hdr.active = 1.0;
    hdr.pos    = float3(sig, sel, drag);
    hdr.dims   = float3(grab.x, grab.y, salt);
    hdr.radius = init;
    hdr.aux    = float3(PLAN_VERSION, phase, tick);   // .x stamp, .y clock, .z last tick
    Cast[SLOT_EDIT] = hdr;
}
