// AX_Plan / plan.hlsl — authors one period of the collage into a durable record buffer.
//
// Single-threaded on purpose: placement is sequential (children need their parents already
// built) and the viewport event queue must be reduced in order. 73 records is nothing.
//
// SELF-SIMILARITY IS STRUCTURAL. Every record's extent is drawn PROPORTIONAL TO ITS PLATE
// RADIUS, so the arrangement is statistically the same at every scale. That is what makes the
// endless zoom read as one continuous world rather than as a slide of stuff getting bigger,
// and it is also what keeps each record's rmax/rmin ratio bounded — a record that spans more
// than one octave interpenetrates its own copy, and the ladder in canvas.hlsl calls that out.
//
// THE LATTICE IS THE RELATIONSHIP. Volumes snap to integer lattice coordinates, so any two of
// them share face planes automatically and a randomized draw still interlocks. Randomizing raw
// coordinates off-lattice would give detached debris no matter how well stratified the draw is.
// Panels, wedges and traces are hosted ON records rather than placed independently.
//
// Regeneration is signature-driven. Structural parameters and the R-key salt rebuild; anything
// else preserves the buffer, so hand edits survive cooks, saves, presets and undo. The focus
// and travel are deliberately OUTSIDE the signature: re-aiming the fall or flying must never
// re-roll the composition, and re-rolling must never jog the flight.
#include "../_shared/axon.hlsli"

RWStructuredBuffer<AxRec> Plan : register(u0);

// Bump whenever the layout algorithm changes, or a recompile silently keeps serving the
// previously generated arrangement out of the persistent buffer.
// 1.1 — traces span to a NEAREST NEIGHBOUR instead of a random volume, and records are drawn
// larger relative to their radius. Both are generation-time, so without this bump the
// persistent buffer keeps serving the old frame-crossing spiderweb and the change does nothing.
// 1.2 — records drawn larger again, and the first few sheets promoted to full backdrop plates.
// 1.3 — backdrop sheets reduced to three at 0.70 of their radius: at 1.05 one plate could cover
// half the frame and the composition became a wall rather than a collage.
#define PLAN_VERSION 1.3

#define AX_PICK_FOCUS (AX_RECORDS + 1u)
#define TAU 6.2831853

// ---------------------------------------------------------------------------
// Placement helpers
// ---------------------------------------------------------------------------

// Stratified ring draw. Angle and log-radius are stratified over DIFFERENT permutations of the
// index: sharing one index walks the records round a spiral, which reads as a decoration rather
// than as a composition.
void ringSlot(uint i, uint n, float rs, float spanV, float ratio, float v,
              out float ang, out float rr)
{
    float fn = max((float)n, 1.0);
    float a0 = ((float)i + 0.5) / fn;
    float a  = a0 + (ax_rnd(rs, 2.0) - 0.5) * (0.55 / fn) * lerp(0.35, 1.0, v);
    ang = a * TAU;

    uint  j  = (i * 13u + 5u) % max(n, 1u);
    float r0 = ((float)j + 0.5) / fn;
    float r  = r0 + (ax_rnd(rs, 3.0) - 0.5) * (0.9 / fn) * lerp(0.35, 1.0, v);
    // 0.12 keeps the innermost record just clear of the aperture the fit will normalize to
    rr = AX_APER_L * pow(ratio, lerp(0.12, spanV, saturate(r)));
}

// Extent drawn from the radius, never from a parallel size parameter. Shape ratios vary, the
// MAGNITUDE does not: that is the whole self-similarity contract.
float3 extentFor(float rr, float rs, float m, float rank, float vert)
{
    // 0.36 rather than a smaller figure on purpose: the reference has almost no empty ground,
    // and at a lower constant the octaves separate into a scatter with black between them.
    float base = max(rr * 0.44 * m * rank, 0.9);
    float3 sh = float3(lerp(0.55, 1.55, ax_rnd(rs, 11.0)),
                       lerp(0.55, 1.55, ax_rnd(rs, 12.0)),
                       lerp(0.35, 1.85, ax_rnd(rs, 13.0)) * vert);
    // one axis occasionally collapses toward a slab, which is where the reference's flat
    // stacked plates come from
    float slab = ax_rnd(rs, 14.0);
    if (slab < 0.22)      sh.z *= 0.22;
    else if (slab < 0.38) sh.y *= 0.28;
    return max(round(base * sh), float3(1.0, 1.0, 1.0));
}

// ---------------------------------------------------------------------------
// Volumes — the axonometric masses. Roughly half attach to an earlier volume of similar size
// so their faces genuinely touch; the rest sit free on the ring. Attachment is what produces
// the reference's interpenetrating stacks, and it is drawn against the PARENT rather than
// against a global coordinate range so a re-roll cannot detach them.
// ---------------------------------------------------------------------------
void buildVolumes(float s, float2 A, float2 B, float2 C)
{
    uint want = (uint)clamp((float)vol_count, 0.0, (float)AX_VOLS);
    float v = saturate(variation);
    float spanV = max(span, 0.3);
    float ratio = max(octave_ratio, 1.05);

    for (uint i = 0u; i < AX_VOLS; i++)
    {
        AxRec r = (AxRec)0;
        float rs = s * 11.7 + (float)i * 29.3 + 101.0;

        float ang, rr;
        ringSlot(i, AX_VOLS, rs, spanV, ratio, v, ang, rr);

        // size hierarchy: two heroes and a supporting cast, preserved under randomization by
        // randomizing around each slot's own rank instead of drawing a flat size
        float rank = 1.0 + 1.05 * exp(-(float)i * 0.62);
        rank *= lerp(1.0, lerp(0.72, 1.34, ax_rnd(rs, 15.0)), v);

        float3 e = extentFor(rr, rs, mass, rank, max(vertical, 0.05));

        float2 tgt = float2(cos(ang), sin(ang)) * rr;
        float2 g = axUnproj(tgt, A, B);
        float zc = (ax_rnd(rs, 16.0) - 0.5) * rr * 0.42 * vertical;
        float3 b = round(float3(g.x - e.x * 0.5, g.y - e.y * 0.5, zc - e.z * 0.5));

        // ATTACHMENT — the exploration axis. `weave` decides what a volume's relationship to
        // its parent IS, which is the only thing about this arrangement worth exploring: the
        // coordinates are already pinned to the lattice and the sizes to the radius.
        // Bias the parent draw toward an early (large, central) record: an unbiased parent
        // chain grows a straggling procession that walks off the ring.
        float attachP = (weave == 1) ? 0.72 : ((weave == 2) ? 0.62 : ((weave == 3) ? 0.14 : 0.50));
        float hostF = 0.0;
        if (i > 1u && ax_rnd(rs, 17.0) < attachP * lerp(1.0, 0.82, v))
        {
            uint p = (uint)floor(ax_rnd(rs, 18.0) * ax_rnd(rs, 19.0) * (float)i);
            p = min(p, i - 1u);
            AxRec pr = Plan[AX_VOL_0 + p];

            // a child inherits its parent's scale band, so the size-to-radius law survives
            e = max(round(e * lerp(0.55, 0.95, ax_rnd(rs, 25.0))), float3(1.0, 1.0, 1.0));

            if (weave == 2)
            {
                // NESTED — the child sits inside the parent's own extent, which is the
                // reference's boxes-within-boxes read. Cap the child against its container or
                // the mass swallows the box it is supposed to be inside.
                e = max(round(min(e, pr.ext * 0.72)), float3(1.0, 1.0, 1.0));
                float3 room = max(pr.ext - e, float3(0.0, 0.0, 0.0));
                b = round(pr.pos + float3(ax_rnd(rs, 22.0), ax_rnd(rs, 23.0), ax_rnd(rs, 24.0)) * room);
            }
            else
            {
                int axis = (weave == 1) ? 2 : (int)floor(ax_rnd(rs, 20.0) * 3.0);
                float sgn = (weave == 1) ? 1.0 : ((ax_rnd(rs, 21.0) < 0.5) ? -1.0 : 1.0);
                // Offsets on the two free axes are drawn strictly BELOW the parent's extent,
                // which guarantees shared solid rather than a pair of cubes touching at a
                // corner and reading as two separate objects.
                float lat = (weave == 1) ? 0.34 : 0.92;
                float3 off = (float3(ax_rnd(rs, 22.0), ax_rnd(rs, 23.0), ax_rnd(rs, 24.0)) - 0.5)
                           * pr.ext * lat;
                float3 nb = pr.pos + round(off);
                if (axis == 0)      nb.x = (sgn > 0.0) ? (pr.pos.x + pr.ext.x) : (pr.pos.x - e.x);
                else if (axis == 1) nb.y = (sgn > 0.0) ? (pr.pos.y + pr.ext.y) : (pr.pos.y - e.y);
                else                nb.z = (sgn > 0.0) ? (pr.pos.z + pr.ext.z) : (pr.pos.z - e.z);
                b = round(nb);
            }
            hostF = (float)(AX_VOL_0 + p) + 1.0;
        }

        // BOTH-WAY RADIAL CLAMP. Clamping only outward lets a small record sit concentric on
        // the focus and swallow the aperture; clamping only inward lets one stray record drag
        // the fit down and shrink the whole composition into a speck.
        {
            float2 ctr = axProj(b + e * 0.5, A, B, C);
            float d = length(ctr);
            float lo = AX_APER_L * 1.18 + length(axProj(e * 0.5, A, B, C)) * 0.55;
            float hi = AX_APER_L * pow(ratio, spanV);
            if (d > 1e-3 && (d < lo || d > hi))
            {
                float2 want = ctr * (clamp(d, lo, hi) / d);
                b = round(b + float3(axUnproj(want - ctr, A, B), 0.0));
            }
        }

        r.pos    = b;
        r.ext    = e;
        r.role   = ROLE_VOL;
        r.kind   = min(floor(ax_rnd(rs, 30.0) * (float)AX_VKINDS), (float)(AX_VKINDS - 1));
        r.seed   = s * 3.3 + (float)i * 17.0 + 1.0;
        r.host   = hostF;
        r.phase  = ax_rnd(rs, 31.0);
        r.flags  = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[AX_VOL_0 + i] = r;
    }
}

// ---------------------------------------------------------------------------
// Panels — the newsprint sheets, register bands and pattern plates. Hosted panels are laid ON
// a volume face (coplanar, nudged out along the face normal so they win the depth test);
// free panels are flat lattice-plane sheets out in the ring.
// ---------------------------------------------------------------------------
void buildPanels(float s, float2 A, float2 B, float2 C)
{
    uint want = (uint)clamp((float)pan_count, 0.0, (float)AX_PANS);
    float v = saturate(variation);
    float spanV = max(span, 0.3);
    float ratio = max(octave_ratio, 1.05);

    for (uint i = 0u; i < AX_PANS; i++)
    {
        AxRec r = (AxRec)0;
        float rs = s * 13.1 + (float)i * 37.7 + 211.0;
        float hostF = 0.0;
        float3 b, e;

        // The first few sheets are BACKDROP PLATES — big free planes carrying a whole register
        // of newsprint or checker. The reference has almost no bare ground; without these the
        // octaves read as a scatter of objects in the dark instead of as a collage.
        bool backdrop = (i < 3u);
        bool hosted = !backdrop && (ax_rnd(rs, 2.0) < 0.55);
        if (hosted)
        {
            uint hv = (uint)min(floor(ax_rnd(rs, 4.0) * (float)AX_VOLS), (float)(AX_VOLS - 1u));
            AxRec h = Plan[AX_VOL_0 + hv];
            int face = (int)floor(ax_rnd(rs, 5.0) * 3.0);
            // extent DERIVED from the host face rather than from a parallel size parameter:
            // one control moves the volume and the sheet on it together, forever
            float2 grow = float2(lerp(0.45, 1.25, ax_rnd(rs, 6.0)), lerp(0.45, 1.25, ax_rnd(rs, 7.0)));
            if (face == AX_FACE_TOP)
            {
                e = float3(max(round(h.ext.x * grow.x), 1.0), max(round(h.ext.y * grow.y), 1.0), 0.0);
                b = float3(h.pos.x, h.pos.y, h.pos.z + h.ext.z + 0.06);
            }
            else if (face == AX_FACE_RIGHT)
            {
                e = float3(0.0, max(round(h.ext.y * grow.x), 1.0), max(round(h.ext.z * grow.y), 1.0));
                b = float3(h.pos.x + h.ext.x + 0.06, h.pos.y, h.pos.z);
            }
            else
            {
                e = float3(max(round(h.ext.x * grow.x), 1.0), 0.0, max(round(h.ext.z * grow.y), 1.0));
                b = float3(h.pos.x, h.pos.y + h.ext.y + 0.06, h.pos.z);
            }
            hostF = (float)(AX_VOL_0 + hv) + 1.0;
        }
        else
        {
            float ang, rr;
            ringSlot(i, AX_PANS, rs, spanV, ratio, v, ang, rr);
            float2 tgt = float2(cos(ang), sin(ang)) * rr;
            float2 g = axUnproj(tgt, A, B);
            float sz = max(rr * (backdrop ? 0.70 : 0.40) * mass, 1.0);
            int plane = (int)floor(ax_rnd(rs, 8.0) * 3.0);
            float3 se = max(round(float3(sz * lerp(0.6, 1.7, ax_rnd(rs, 9.0)),
                                         sz * lerp(0.6, 1.7, ax_rnd(rs, 10.0)),
                                         sz * lerp(0.5, 1.4, ax_rnd(rs, 11.0)))), float3(1.0, 1.0, 1.0));
            if (plane == 0)      se.z = 0.0;
            else if (plane == 1) se.x = 0.0;
            else                 se.y = 0.0;
            e = se;
            float zc = (ax_rnd(rs, 12.0) - 0.5) * rr * 0.42 * vertical;
            b = round(float3(g.x - e.x * 0.5, g.y - e.y * 0.5, zc - e.z * 0.5));
        }

        r.pos    = b;
        r.ext    = e;
        r.role   = ROLE_PAN;
        // the register bands (GRID / STRIP) are what carry the reference's checker floor and
        // its newsprint columns, so they are deliberately common rather than rare
        r.kind   = min(floor(ax_rnd(rs, 13.0) * (float)AX_PKINDS), (float)(AX_PKINDS - 1));
        r.seed   = s * 7.1 + (float)i * 23.0 + 5.0;
        r.host   = hostF;
        r.phase  = ax_rnd(rs, 14.0);
        r.flags  = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[AX_PAN_0 + i] = r;
    }
}

// ---------------------------------------------------------------------------
// Wedges — the reference's hard triangles. Always HALF OF A REAL FACET rather than a floating
// triangle: that is why they read as the collage being cut rather than as shapes dropped on it.
// ---------------------------------------------------------------------------
void buildWedges(float s, float2 A, float2 B, float2 C)
{
    uint want = (uint)clamp((float)wdg_count, 0.0, (float)AX_WDGS);
    for (uint i = 0u; i < AX_WDGS; i++)
    {
        AxRec r = (AxRec)0;
        float rs = s * 17.3 + (float)i * 41.1 + 307.0;

        uint hv = (uint)min(floor(ax_rnd(rs, 2.0) * (float)AX_VOLS), (float)(AX_VOLS - 1u));
        AxRec h = Plan[AX_VOL_0 + hv];
        int face = (int)floor(ax_rnd(rs, 3.0) * 3.0);
        float grow = lerp(0.75, 1.6, ax_rnd(rs, 4.0));
        float3 b, e;
        if (face == AX_FACE_TOP)
        {
            e = float3(max(round(h.ext.x * grow), 1.0), max(round(h.ext.y * grow), 1.0), 0.0);
            b = float3(h.pos.x, h.pos.y, h.pos.z + h.ext.z + 0.14);
        }
        else if (face == AX_FACE_RIGHT)
        {
            e = float3(0.0, max(round(h.ext.y * grow), 1.0), max(round(h.ext.z * grow), 1.0));
            b = float3(h.pos.x + h.ext.x + 0.14, h.pos.y, h.pos.z);
        }
        else
        {
            e = float3(max(round(h.ext.x * grow), 1.0), 0.0, max(round(h.ext.z * grow), 1.0));
            b = float3(h.pos.x, h.pos.y + h.ext.y + 0.14, h.pos.z);
        }

        r.pos    = b;
        r.ext    = e;
        r.role   = ROLE_WDG;
        r.kind   = min(floor(ax_rnd(rs, 5.0) * 4.0), 3.0);   // which corner the diagonal keeps
        r.seed   = s * 5.9 + (float)i * 31.0 + 9.0;
        r.host   = (float)(AX_VOL_0 + hv) + 1.0;
        r.phase  = ax_rnd(rs, 6.0);
        r.flags  = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[AX_WDG_0 + i] = r;
    }
}

// ---------------------------------------------------------------------------
// Traces — the bright hairlines. Every one SPANS FROM ONE VOLUME'S CORNER TO ANOTHER'S, so
// the line always explains a relationship in the arrangement. A free line drawn anywhere is
// the single fastest way to make this composition look like decoration.
// ---------------------------------------------------------------------------
void buildTraces(float s, float2 A, float2 B, float2 C)
{
    uint want = (uint)clamp((float)trc_count, 0.0, (float)AX_TRCS);
    for (uint i = 0u; i < AX_TRCS; i++)
    {
        AxRec r = (AxRec)0;
        float rs = s * 19.7 + (float)i * 43.3 + 401.0;

        uint va = (uint)min(floor(ax_rnd(rs, 2.0) * (float)AX_VOLS), (float)(AX_VOLS - 1u));
        AxRec ra = Plan[AX_VOL_0 + va];
        float2 ca = axProj(ra.pos + ra.ext * 0.5, A, B, C);

        // The far end is a NEAREST NEIGHBOUR, not a random volume. Drawing the far end freely
        // gives lines that cross the whole plate, and because every octave draws its own copy
        // that compounds into a spiderweb over the composition instead of routing inside it.
        // Skipping the closest few keeps the runs from collapsing onto contact points.
        uint skip = (uint)floor(ax_rnd(rs, 3.0) * 3.0);
        uint vb = (va + 1u) % AX_VOLS; float bestD = 1e9;
        for (uint k = 0u; k < AX_VOLS; k++)
        {
            if (k == va) continue;
            AxRec rc = Plan[AX_VOL_0 + k];
            float d = length(axProj(rc.pos + rc.ext * 0.5, A, B, C) - ca)
                    + ax_rnd(rs + (float)k, 9.0) * 0.6;
            if (k % 3u == skip) d *= 0.55;      // a stable, seed-driven choice among near ones
            if (d < bestD) { bestD = d; vb = k; }
        }
        AxRec rb = Plan[AX_VOL_0 + vb];

        int cnA = (int)min(floor(ax_rnd(rs, 4.0) * 8.0), 7.0);
        int cb = (int)min(floor(ax_rnd(rs, 5.0) * 8.0), 7.0);
        float3 pa = ra.pos + float3(((cnA & 1) != 0) ? ra.ext.x : 0.0,
                                    ((cnA & 2) != 0) ? ra.ext.y : 0.0,
                                    ((cnA & 4) != 0) ? ra.ext.z : 0.0);
        float3 pb = rb.pos + float3(((cb & 1) != 0) ? rb.ext.x : 0.0,
                                    ((cb & 2) != 0) ? rb.ext.y : 0.0,
                                    ((cb & 4) != 0) ? rb.ext.z : 0.0);

        r.pos    = pa;
        r.ext    = pb - pa;
        r.role   = ROLE_TRC;
        r.kind   = min(floor(ax_rnd(rs, 6.0) * (float)AX_TKINDS), (float)(AX_TKINDS - 1));
        r.seed   = s * 23.1 + (float)i * 13.0 + 3.0;
        r.host   = (float)(AX_VOL_0 + va) + 1.0;
        r.phase  = ax_rnd(rs, 7.0);
        r.flags  = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[AX_TRC_0 + i] = r;
    }
}

// ---------------------------------------------------------------------------
// Pick. Draw and hit test route through the SAME projection, so a handle is grabbable exactly
// where it appears. Smallest hit wins, so a small record resting on a hero stays reachable.
// ---------------------------------------------------------------------------
uint pickRecord(float2 uv, float2 f2, float viewHalf, float2 A, float2 B, float2 C, float3 D,
                out int region)
{
    region = axRegionAt(uv);
    uint best = 0u; float bestScore = 1e9;

    if (region == 1)
    {
        // the focus reticle first: it is small, always on top, and the highest-value handle
        if (length((uv - axPlateToUv(float2(0.0, 0.0), viewHalf)) * float2(1.0 / AX_ASPECT, 1.0)) < 0.022)
            return AX_PICK_FOCUS;

        float2 q = f2 + axUvToPlate(uv, viewHalf);
        for (uint i = 0u; i < AX_RECORDS - 1u; i++)
        {
            AxRec r = Plan[i];
            if (r.active < 0.5) continue;
            if (r.role == ROLE_TRC)
            {
                float2 p0 = axProj(r.pos, A, B, C);
                float2 p1 = axProj(r.pos + r.ext, A, B, C);
                float d = axSegD(q, p0, p1);
                float tol = viewHalf * 0.014;
                if (d < tol && d < bestScore) { bestScore = d; best = i + 1u; }
            }
            else
            {
                int face; float2 fl; float dep;
                if (axBoxHit(r.pos, r.ext, q, A, B, C, D, face, fl, dep))
                {
                    float2 ctr; float rad;
                    axBound(r.pos, r.ext, A, B, C, ctr, rad);
                    if (rad < bestScore) { bestScore = rad; best = i + 1u; }
                }
            }
        }
        return best;
    }

    if (region == 2)
    {
        // the ladder: pick the record whose BAR the pointer is on, by row
        float spanView = max(span, 0.3) + 0.65;
        float rho = axXToRho(uv.x, spanView);
        float rowH = (AX_LAD_Y1 - AX_LAD_Y0) / (float)(AX_RECORDS - 1u);
        int row = (int)floor((uv.y - AX_LAD_Y0) / max(rowH, 1e-5));
        if (row >= 0 && row < (int)(AX_RECORDS - 1u))
        {
            AxRec r = Plan[(uint)row];
            float ratio = max(octave_ratio, 1.05);
            if (r.active > 0.5 && rho >= axRho(r.rmin, ratio) - 0.12 && rho <= axRho(r.rmax, ratio) + 0.12)
                return (uint)row + 1u;
        }
        return 0u;
    }
    return 0u;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    AxRec hdr = Plan[AX_HEADER];
    // The header's edit bits ride INSIDE hdr.flags alongside the init flag rather than in a
    // field of their own. That is not tidiness — it is a migration guarantee. hdr.active once
    // carried a live tally, and when the header was repacked the old tally was still sitting
    // there and got read as flags: a stored 10 has bit 2 set, so F_EDITED latched on, the focus
    // was permanently considered hand-moved, and focus_x / focus_y silently stopped doing
    // anything. Encoding as 1 + hflags*4 means any buffer written before this change decodes to
    // hflags = 0, which is the correct starting state.
    float initFlag = (hdr.flags >= 0.5) ? 1.0 : 0.0;
    float salt     = hdr.seed;
    float sel      = hdr.pos.y;
    float dragOn   = hdr.pos.z;
    float2 grab    = float2(hdr.ext.x, hdr.ext.y);
    float travel   = hdr.pad2;                    // persistent accumulator, never reset
    float2 focusL  = float2(hdr.pad0, hdr.pad1);  // focus in LATTICE ground coordinates
    uint  hflags   = (initFlag > 0.5) ? (uint)max(round((hdr.flags - 1.0) / 4.0), 0.0) : 0u;

    float2 A, B, C; float3 D;
    axBasis((int)lattice, A, B, C, D);
    float viewHalf = axViewHalf(span, octave_ratio);

    uint n = min((uint)_ViewportEventCount, 64u);

    // --- pass 1: keys. R changes the salt, so it has to land before the signature test.
    for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];
        if (ev.type == 4u && ev.phase == 1u)
        {
            uint c = (uint)ev.code;
            if (c == 18u) salt += 1.0;                       // R  reseed
            else if (c == 26u)                               // Z  revert to the shipped arrangement
            {
                // The salt only ever INCREMENTS, and it is in the signature — so without this
                // key one press of R puts the shipped arrangement permanently out of reach, and
                // "variation = 0 is the transcription, so it can never be lost" becomes false.
                // Z zeroes it, releases the focus back to its parameters, and forces the rebuild
                // branch regardless of the signature.
                //
                // It reverts the BUFFER, not Properties: a module cannot write its own
                // parameters, so weave / lattice / seed / counts stay where the user set them.
                // Recall the "Arrangement — Shipped" preset to put those back too.
                salt = 0.0;
                hflags &= ~F_EDITED;
                sel = 0.0;
                dragOn = 0.0;
                initFlag = 0.0;
            }
            else if (c == 3u) sel = 0.0;                     // C  clear selection
            else if (c == 6u)                                // F  focus on pointer
            {
                float2 p = _ViewportPointerPosition;
                if (axRegionAt(p) == 1)
                {
                    float2 q = axProj(float3(focusL, 0.0), A, B, C) + axUvToPlate(p, viewHalf);
                    focusL = axUnproj(q, A, B);
                    hflags |= F_EDITED;
                }
            }
            else if (sel > 0.5 && sel < (float)AX_RECORDS)
            {
                uint idx = (uint)(sel - 1.0);
                AxRec r = Plan[idx];
                uint fl = (uint)r.flags;
                if (c == 23u)      { r.pos.z += 1.0; fl |= F_EDITED; }                       // W raise
                else if (c == 19u) { r.pos.z -= 1.0; fl |= F_EDITED; }                       // S lower
                else if (c == 5u)                                                            // E grow
                {
                    // sign() keeps a panel's zero extent at zero, so growing a sheet can never
                    // silently inflate it into a solid
                    if (r.role == ROLE_TRC) r.ext *= 1.15;
                    else r.ext = min(round(r.ext * 1.25 + 0.5 * sign(r.ext)), 96.0);
                    fl |= F_EDITED;
                }
                else if (c == 17u)                                                           // Q shrink
                {
                    if (r.role == ROLE_TRC) r.ext *= 0.87;
                    else r.ext = max(round(r.ext * 0.8), sign(r.ext));
                    fl |= F_EDITED;
                }
                else if (c == 11u)                                                           // K cycle form
                {
                    float kinds = (r.role == ROLE_VOL) ? (float)AX_VKINDS
                                : (r.role == ROLE_PAN) ? (float)AX_PKINDS
                                : (r.role == ROLE_TRC) ? (float)AX_TKINDS : 4.0;
                    r.kind = fmod(r.kind + 1.0, kinds);
                    fl |= F_EDITED;
                }
                else if (c == 13u) { r.mat = fmod(r.mat + 1.0, (float)AX_MATS); fl |= F_EDITED | F_MATLOCK; } // M
                else if (c == 16u) { r.col = fmod(r.col + 1.0, (float)AX_COLS); fl |= F_EDITED | F_MATLOCK; } // P
                else if (c == 24u) { r.active = (r.active > 0.5) ? 0.0 : 1.0; fl |= F_EDITED; }               // X
                else if (c == 14u)                                                           // N re-roll
                {
                    r.seed += 7.77;
                    r.kind = floor(ax_rnd(r.seed, 1.0) * ((r.role == ROLE_VOL) ? (float)AX_VKINDS
                                                        : (r.role == ROLE_PAN) ? (float)AX_PKINDS
                                                        : (r.role == ROLE_TRC) ? (float)AX_TKINDS : 4.0));
                    r.phase = ax_rnd(r.seed, 2.0);
                    fl = (fl | F_EDITED) & ~F_MATLOCK;       // let the refresh redraw its paper
                }
                r.flags = (float)fl;
                Plan[idx] = r;
            }
        }
    }

    // Structural signature. The focus, travel, materials and palette are deliberately absent:
    // re-aiming the fall or restyling the paper must never wipe an arrangement the user built.
    float sig = seed * 7.31 + (float)vol_count * 1.13 + (float)pan_count * 2.17
              + (float)wdg_count * 3.31 + (float)trc_count * 5.11
              + (float)lattice * 37.7 + (float)weave * 29.9 + variation * 137.9 + span * 53.1
              + octave_ratio * 97.3 + mass * 71.3 + vertical * 61.3
              + salt * 101.3 + PLAN_VERSION * 911.7;

    if (initFlag < 0.5 || abs(sig - hdr.pos.x) > 1e-4)
    {
        float s = seed + salt * 3.19;
        buildVolumes(s, A, B, C);
        buildPanels(s, A, B, C);
        buildWedges(s, A, B, C);
        buildTraces(s, A, B, C);
        sel = 0.0; dragOn = 0.0;
        if ((hflags & F_EDITED) == 0u) focusL = float2(focus_x, focus_y);
    }

    // --- pass 2: pointer.
    float2 f2 = axProj(float3(focusL, 0.0), A, B, C);
    for (uint e2 = 0u; e2 < n; e2++)
    {
        ViewportEvent ev = _ViewportEvents[e2];
        if (ev.type != 5u) continue;
        float2 p = ev.position;

        if (ev.code == 1u && ev.phase == 7u)                 // click: select
        {
            int rg;
            sel = (float)pickRecord(p, f2, viewHalf, A, B, C, D, rg);
        }
        else if (ev.code == 3u)                              // drag
        {
            if (ev.phase == 5u)
            {
                int rg;
                uint hit = pickRecord(p, f2, viewHalf, A, B, C, D, rg);
                sel = (float)hit;
                dragOn = 0.0;
                if (hit == AX_PICK_FOCUS)
                {
                    dragOn = 3.0;
                    grab = focusL - axUnproj(f2 + axUvToPlate(p, viewHalf), A, B);
                }
                else if (hit != 0u)
                {
                    dragOn = (float)rg;
                    AxRec r = Plan[hit - 1u];
                    if (rg == 1)
                    {
                        float2 g = axUnproj(f2 + axUvToPlate(p, viewHalf), A, B);
                        grab = r.pos.xy - g;
                    }
                    else
                    {
                        float spanView = max(span, 0.3) + 0.65;
                        grab = float2(axRho(max(r.rmin, 1e-3), max(octave_ratio, 1.05))
                                      - axXToRho(p.x, spanView), 0.0);
                    }
                }
            }
            else if (ev.phase == 6u && dragOn > 0.5)
            {
                if (dragOn > 2.5)
                {
                    focusL = axUnproj(f2 + axUvToPlate(p, viewHalf), A, B) + grab;
                    hflags |= F_EDITED;
                }
                else if (sel > 0.5 && sel < (float)AX_RECORDS)
                {
                    uint idx = (uint)(sel - 1.0);
                    AxRec r = Plan[idx];
                    if (dragOn < 1.5)
                    {
                        // THE PLATE strip owns lateral placement: the record slides on the
                        // ground plane and stays snapped to the lattice, so dragging can never
                        // knock a volume off the grid that makes it interlock.
                        float2 g = axUnproj(f2 + axUvToPlate(p, viewHalf), A, B) + grab;
                        r.pos.xy = round(g);
                    }
                    else
                    {
                        // THE LADDER strip owns radius: the same handle, pushed in or out along
                        // its own bearing from the focus. That is the edit the plate cannot
                        // express precisely, because one octave of radius is a long way on the
                        // plate and a few millimetres on the ladder.
                        float spanView = max(span, 0.3) + 0.65;
                        float ratio = max(octave_ratio, 1.05);
                        float rhoNew = axXToRho(p.x, spanView) + grab.x;
                        float2 ctr = axProj(r.pos + r.ext * 0.5, A, B, C);
                        float2 dv = ctr - f2;
                        float dl = max(length(dv), 1e-3);
                        float rNew = AX_APER_L * pow(ratio, clamp(rhoNew, -0.4, spanView));
                        float scaleK = clamp(rNew / max(r.rmin, 1e-3), 0.2, 6.0);
                        float2 ctrNew = f2 + dv / dl * (dl * scaleK);
                        r.pos.xy = round(r.pos.xy + axUnproj(ctrNew - ctr, A, B));
                    }
                    r.flags = (float)(((uint)r.flags) | F_EDITED);
                    Plan[idx] = r;
                }
            }
            else { dragOn = 0.0; }
        }
    }

    f2 = axProj(float3(focusL, 0.0), A, B, C);

    // --- appearance refresh. Materials and colour are NOT in the signature and are republished
    // every cook, so restyling the paper never costs a layout the user dragged into place. A
    // record whose paper was set by hand carries F_MATLOCK and is left alone.
    {
        float pv = saturate(paper);
        for (uint i = 0u; i < AX_RECORDS - 1u; i++)
        {
            AxRec r = Plan[i];
            if (((uint)r.flags & F_MATLOCK) != 0u) continue;
            float h1 = ax_rnd(r.seed, 51.0);
            float h2 = ax_rnd(r.seed, 52.0);
            if (r.role == ROLE_TRC)
            {
                // vermilion and cyan carry most of the line work in the reference; green is a
                // rare punctuation, so an even draw over four inks reads far greener than the
                // reference ever does
                r.mat = 0.0;
                r.col = (h2 < 0.40) ? 0.0 : ((h2 < 0.74) ? 1.0 : ((h2 < 0.86) ? 2.0 : 3.0));
            }
            else
            {
                // paper biases the draw between printed stock and flat colour; the pattern
                // plates sit between them so the composition never becomes all one or all other
                float m;
                if (h1 < pv * 0.62)              m = (h2 < 0.62) ? (float)AX_M_NEWS : (float)AX_M_HEAD;
                else if (h1 < pv * 0.62 + 0.26)  m = 2.0 + floor(ax_rnd(r.seed, 53.0) * 4.0);  // HOUND..HALF
                else                             m = (ax_rnd(r.seed, 54.0) < 0.78) ? (float)AX_M_SOLID
                                                                                   : (float)AX_M_BARS;
                // The backdrop sheets and the two hero volumes are forced CALM — a plain sheet
                // of stock or a flat plane. They are the largest areas in the frame, and a
                // pattern on them makes the whole composition uniformly busy with nowhere for
                // the eye to rest, which is the one thing the reference never does.
                bool calm = (i < 2u) || (i >= AX_PAN_0 && i < AX_PAN_0 + 3u);
                if (calm) m = (ax_rnd(r.seed, 59.0) < 0.62) ? (float)AX_M_NEWS : (float)AX_M_SOLID;
                r.mat = m;
                // Printed stock stays in the paper greys. Flat plates are mostly paper, black
                // and grey too, with the hot chord used as PUNCTUATION — an even draw over the
                // saturated end reads as neon, and the reference is a grey-and-newsprint field
                // with a handful of loud planes cut into it.
                float cr = ax_rnd(r.seed, 55.0);
                if (m <= (float)AX_M_HEAD) r.col = (cr < 0.72) ? 9.0 : ((cr < 0.9) ? 10.0 : 8.0);
                else if (m <= (float)AX_M_HALF) r.col = (cr < 0.55) ? 7.0 : ((cr < 0.8) ? 10.0 : floor(cr * 7.0));
                else
                {
                    float c2 = ax_rnd(r.seed, 56.0);
                    // wedges are the exception: the reference's triangles are where the loudest
                    // colour in the whole picture lives, signal green included
                    if (r.role == ROLE_WDG) r.col = (c2 < 0.16) ? 11.0 : floor(c2 * 7.0);
                    else r.col = (c2 < 0.68) ? (7.0 + floor(ax_rnd(r.seed, 57.0) * 4.0))
                                             : floor(ax_rnd(r.seed, 58.0) * 7.0);
                }
            }
            Plan[i] = r;
        }
    }

    // --- derived radii + the fit. cell is chosen so the NEAREST record edge lands exactly on
    // the requested plate aperture: one uniform similarity on the lattice unit, so no
    // proportion anywhere changes and any seed frames itself.
    float cRmin = 1e9, cRmax = 0.0;
    uint liveV = 0u, liveP = 0u, liveW = 0u, liveT = 0u;
    for (uint i2 = 0u; i2 < AX_RECORDS - 1u; i2++)
    {
        AxRec r = Plan[i2];
        float rn, rx;
        axRadial(r, f2, A, B, C, rn, rx);
        r.rmin = rn; r.rmax = rx;
        uint f = (uint)r.flags;
        f = (sel > 0.5 && sel < (float)AX_RECORDS && (uint)(sel - 1.0) == i2) ? (f | F_SELECTED)
                                                                             : (f & ~F_SELECTED);
        r.flags = (float)f;
        Plan[i2] = r;

        if (r.active > 0.5)
        {
            cRmin = min(cRmin, rn); cRmax = max(cRmax, rx);
            if (r.role == ROLE_VOL) liveV++;
            else if (r.role == ROLE_PAN) liveP++;
            else if (r.role == ROLE_WDG) liveW++;
            else if (r.role == ROLE_TRC) liveT++;
        }
    }
    if (cRmin > 1e8) { cRmin = AX_APER_L; cRmax = AX_APER_L * 4.0; }
    float cell = aperture / max(cRmin, 0.35);

    // TRAVEL. Integrated against _DeltaTime, never rate x absolute time, so changing speed
    // mid-flight does not teleport the collage. The loop is `period` OCTAVES long: after that
    // many, every layer has taken over the slot of the layer one step nearer and the frame
    // repeats exactly.
    float P = max((float)period, 1.0);
    travel = frac(travel / P + _DeltaTime * fall_speed / P) * P;
    float travelOut = frac(travel / P + phase) * P;

    // The header is the whole downstream contract. Projection, octave ratio and loop period
    // live here rather than being declared again on the renderer: a second copy of any of them
    // is a second authority for the same number, and the two would silently disagree at every
    // setting nobody personally tested.
    hdr.pos    = float3(sig, sel, dragOn);
    hdr.ext    = float3(grab.x, grab.y, cell);
    hdr.role   = ROLE_HEADER;
    hdr.kind   = (float)lattice;
    hdr.seed   = salt;
    hdr.mat    = octave_ratio;
    hdr.col    = (float)period;
    hdr.host   = axPackCounts(liveV, liveP, liveW, liveT);
    hdr.rmin   = cRmin;
    hdr.rmax   = cRmax;
    hdr.phase  = travelOut;
    hdr.flags  = 1.0 + (float)hflags * 4.0;   // init flag + the header's edit bits, see the top
    hdr.active = 1.0;
    hdr.pad0   = focusL.x;
    hdr.pad1   = focusL.y;
    hdr.pad2   = travel;
    Plan[AX_HEADER] = hdr;
}
