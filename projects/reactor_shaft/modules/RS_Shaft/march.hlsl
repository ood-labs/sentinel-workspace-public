// RS_Shaft / march.hlsl — ray-marches the shaft RS_Plan authored.
//
// It owns Sentinel's internal camera, the light, the surface and the volume. It re-decides
// NOTHING about placement: every block, every lamp and the core come out of the record buffer.
//
// HOW THE INFINITE ZOOM WORKS. The camera never moves. The shaft scrolls through it: every
// field is sampled at (world z + travel), every field is periodic with RS_LOOP_Z, and travel
// wraps at exactly that period — so the frame at travel = 0 and the frame at travel = RS_LOOP_Z
// are the same frame down to the bit. There is no crossfade and no teleport to hide.
//
// WHY THE CORE NEVER ARRIVES. A genuinely endless straight tube converges to a vanishing POINT,
// and anything at infinity down one would be a dot. So the tube is CUT by a plane a fixed
// distance ahead of the eye and the core is shown through the hole. The cut travels with you.
// You fly forever and the core never gets closer. That is the dream logic the reference is about.
//
// THE COST TRICK. Evaluating nine fixture boxes at every march step would be unaffordable. But
// every fixture lives inside the shell {distance-to-wall <= shell}, and the bore field is
// 1-Lipschitz, so a point further than `shell` from the wall is provably at least (d - shell)
// from any fixture. Steps down the middle of the tube therefore cost one bore evaluation, and
// the nine boxes are only paid for in the thin skin where they can actually be hit.
#include "../_shared/shaft.hlsli"

StructuredBuffer<RsRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static float g_travel;
static int   g_style;

#define MAT_WALL   0
#define MAT_RAIL   1
#define MAT_FIX    2
#define MAT_LIGHT  3
#define MAT_CORE   4

struct Hit
{
    float  d;
    int    mat;
    int    kind;     // fixture kind, or light kind
    float  tone;     // surface value / intensity
    float3 emis;     // emissive colour, already scaled
    int    face;
    float2 suv;      // surface coordinates: (along the face, along the shaft)
};

Hit hitInit()
{
    Hit h;
    h.d = 1e9; h.mat = MAT_WALL; h.kind = 0; h.tone = 0.5;
    h.emis = float3(0.0, 0.0, 0.0); h.face = 0; h.suv = float2(0.0, 0.0);
    return h;
}

RsProfile profileAt(float zs)
{
    int i0, i1, i2, i3; float t;
    rs_staFrame(rs_wrapZ(zs), i0, i1, i2, i3, t);
    return rs_profileFrom(Plan[RS_STA_0 + (uint)i0], Plan[RS_STA_0 + (uint)i1],
                          Plan[RS_STA_0 + (uint)i2], Plan[RS_STA_0 + (uint)i3], t);
}

// ---------------------------------------------------------------------------
// Shape primitives
// ---------------------------------------------------------------------------
float sdBox3(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdCapZ(float3 p, float h, float r)
{
    float3 q = p; q.z -= clamp(q.z, -h, h);
    return length(q) - r;
}
float sdCapX(float3 p, float h, float r)
{
    float3 q = p; q.x -= clamp(q.x, -h, h);
    return length(q) - r;
}

// ---------------------------------------------------------------------------
// The wall. Continuous features live here rather than in records: the long conduit rails that
// run the whole length of the shaft, and the panel relief. Anything CONTINUOUS along z is
// automatically periodic and needs no record; anything DISCRETE and editable is a record.
// ---------------------------------------------------------------------------
float wallDist(float3 p, RsProfile pf, out int wface, out float wu)
{
    float2 q = p.xy - pf.c;
    float d = rs_bore(p.xy, pf, g_style);

    // which face is nearest — needed for material coordinates and for the rails
    float best = -1e9; wface = 0; wu = 0.0;
    [unroll] for (int f = 0; f < 3; f++)
    {
        float a = pf.roll + (float)f * 2.0943951 + 1.5707963;
        float2 n = float2(cos(a), sin(a));
        float pr = dot(q, n);
        if (pr > best) { best = pr; wface = f; wu = dot(q, float2(-n.y, n.x)) / max(pf.rin, 1e-3); }
    }

    // MICRO-RELIEF. The reference's walls are not flat panels with paint on them, they are made
    // of hundreds of small units standing proud of each other. Three record-driven blocks per
    // station give the readable structure; this gives the density, at the cost of one hash.
    //
    // It is a real box repetition rather than a per-cell offset added to the bore field: adding
    // a per-cell constant makes the field discontinuous at every cell wall and the marcher walks
    // straight through the cliff. Bounding by the cell footprint keeps it steppable.
    // Distance LOD. Thousands of centimetre-scale boxes at twenty units are smaller than a pixel,
    // and geometry smaller than a pixel does not read as detail — it reads as a boiling moire
    // that no amount of antialiasing fixes and that the bloom then amplifies. Fading the relief
    // out with distance costs nothing visible and removes the shimmer entirely.
    float dcam = length(p - _CameraPos);
    float rfade = saturate(1.0 - (dcam - relief_near) / max(relief_fade, 0.1));
    if (relief_amount > 0.001 && rfade > 0.001)
    {
        // longitudinal size FIXED and dividing the loop exactly; the per-station panel scale
        // drives the lateral size only (see RS_PANEL_CELLS)
        float ps = RS_PANEL_Z;
        float lat = 4.2 / max(pf.panel, 0.15);
        float2 cw = float2(pf.rin / lat, ps);                  // cell size, world units
        float2 pc = float2(wu * lat, rs_wrapZ(p.z + g_travel) / ps);
        float2 cid = floor(pc);
        float2 fc = (frac(pc) - 0.5) * cw;
        float2 rh = rs_hash22(cid + (float)wface * 31.0);
        // A COARSE GATE over the fine cells. Relieving every cell equally makes the whole wall
        // uniformly bumpy, and a uniformly busy surface reads as noise — the reference's walls
        // work because big smooth slabs sit next to dense clusters. This gives that hierarchy
        // for one extra hash: patches of wall stay flat, patches get deep relief.
        // the coarse divisor also has to divide the loop exactly, or the patch gate strobes
        float2 coarse = floor(float2(wu * 1.05, rs_wrapZ(p.z + g_travel) / (ps * RS_COARSE_DIV)));
        float2 ch = rs_hash22(coarse + (float)wface * 7.0 + 101.0);
        float patch = (ch.x > 0.20) ? (0.35 + 1.25 * ch.y) : 0.0;
        if (rh.x > 0.42 && patch > 0.0)
        {
            float e = (0.014 + rh.y * 0.060) * pf.rin * relief_amount * patch * rfade;
            float2 g2 = abs(fc) - cw * (0.30 + rh.y * 0.16);
            float lateral = max(g2.x, g2.y);
            d = min(d, max(d - e, lateral));
        }
    }
    return d;
}

// Conduit rails: two per face, running the full length. They are the reference's long pipes,
// and being continuous along z they cost nothing to keep seamless.
float railDist(float3 p, RsProfile pf, float amt)
{
    if (amt <= 0.001) return 1e9;
    float2 q = p.xy - pf.c;
    float d = 1e9;
    [unroll] for (int f = 0; f < 3; f++)
    {
        float a = pf.roll + (float)f * 2.0943951 + 1.5707963;
        float2 n = float2(cos(a), sin(a));
        float2 t = float2(-n.y, n.x);
        float ln = pf.rin - dot(q, n);      // inward depth from this face plane
        float lt = dot(q, t) / max(pf.rin, 1e-3);
        [unroll] for (int k = 0; k < 2; k++)
        {
            float u0 = (k == 0) ? -1.16 : 1.16;
            float rr = 0.052 * amt * pf.rin;
            float2 dd = float2((lt - u0) * pf.rin, ln - rr * 0.75);
            float cyl = length(dd) - rr;
            // clamp collars every 1.5 units so the pipe reads as a run of pipe, not a wire
            float zc = p.z + g_travel;
            float zf = abs(frac(zc / 1.5) - 0.5) * 1.5;
            float collar = length(float2(length(dd) - rr * 0.55, zf - 0.05)) - 0.055 * amt * pf.rin;
            d = min(d, min(cyl, collar));
        }
    }
    return d;
}

// ---------------------------------------------------------------------------
// One fixture. `zc` is the fixture's centre in SHAFT coordinates; the caller supplies the
// profile at that z, so the block is always flush with the wall it is bolted to.
// ---------------------------------------------------------------------------
float fixDist(float3 p, RsRec r, RsProfile pf, float zc, float detail)
{
    RsFixGeo g = rs_fixGeo(r, pf);
    float2 q = p.xy - (g.face + g.nIn * g.pr * 0.5);
    float3 l = float3(dot(q, g.tang), dot(q, g.nIn), (p.z + g_travel) - zc);
    float3 h = float3(g.hw, g.pr * 0.5, g.zh);
    int k = (int)r.kind;

    if (k == FK_DRUM)
    {
        // a tank lying across the wall
        float rr = min(g.pr * 0.9, g.zh * 0.9);
        return sdCapX(float3(l.x, l.y - (g.pr * 0.5 - rr), l.z), max(g.hw - rr, 0.0), rr);
    }

    float d = sdBox3(l, h) - min(h.y, h.z) * 0.08;    // bevelled edges on everything

    if (k == FK_STACK)
    {
        float3 l2 = l - float3(0.0, h.y * 0.75, 0.0);
        float3 h2 = float3(h.x * 0.58, h.y * 0.55, h.z * 0.62);
        d = min(d, sdBox3(l2, h2) - h2.y * 0.25);
    }
    else if (k == FK_BEAM)
    {
        // an I-section: waist cut out of both sides
        float waist = max(abs(l.z) - h.z * 0.34, 0.0);
        d = max(d, -(max(h.y * 0.55 - abs(l.y), 0.0) - waist * 4.0) * 0.6);
    }

    if (detail > 0.5)
    {
        if (k == FK_FINS)
        {
            // REAL grooves cut into the inner face. This is the hero greeble in the reference
            // and it is the one that has to survive being looked at closely.
            float pitch = max(h.z * 2.0 / max(floor(h.z * 26.0), 3.0), 0.012);
            float zf = l.z - pitch * floor(l.z / pitch + 0.5);
            float depth = h.y * 1.25;
            float gr = max(abs(zf) - pitch * 0.30, (h.y - depth) - l.y);
            d = max(d, -gr);
        }
        else if (k == FK_GRILLE)
        {
            // real perforation, repeated in both surface axes
            float px2 = max(h.x * 2.0 / max(floor(h.x * 16.0), 2.0), 0.02);
            float pz2 = max(h.z * 2.0 / max(floor(h.z * 16.0), 2.0), 0.02);
            float xf = l.x - px2 * floor(l.x / px2 + 0.5);
            float zf = l.z - pz2 * floor(l.z / pz2 + 0.5);
            float cell = max(max(abs(xf) - px2 * 0.32, abs(zf) - pz2 * 0.32),
                             (h.y - h.y * 1.1) - l.y);
            d = max(d, -cell);
        }
    }
    return d;
}

// ---------------------------------------------------------------------------
// One light.
// ---------------------------------------------------------------------------
float lightDist(float3 p, RsRec r, RsProfile pf, float zc)
{
    float2 tg;
    float2 sp = rs_lightSection(r, pf, tg);
    float2 q = p.xy - sp;
    float3 l = float3(dot(q, tg), dot(q, float2(-tg.y, tg.x)), (p.z + g_travel) - zc);
    int k = (int)r.kind;
    float rr = max(r.size.y, 0.008);

    if (k == LK_RUN)  return sdCapZ(l, max(r.size.x, 0.01), rr);
    if (k == LK_BAR)  return sdCapX(l, max(r.size.x, 0.01), rr);
    if (k == LK_FLOOD)
    {
        // a lamp in a shallow housing: the housing is what gives it a hard bright edge
        float lamp = length(l) - rr;
        float hous = sdCapZ(l - float3(0.0, -rr * 0.55, 0.0), rr * 0.9, rr * 1.35);
        return min(lamp, max(hous, -(length(l) - rr * 1.02)));
    }
    return length(l) - rr;
}

// ---------------------------------------------------------------------------
// The scene. `full` fills the material fields; the march path leaves them alone.
// ---------------------------------------------------------------------------
Hit mapFull(float3 p, bool full)
{
    Hit best = hitInit();
    float zs = p.z + g_travel;
    RsProfile pf = profileAt(zs);

    int wface; float wu;
    float dw = wallDist(p, pf, wface, wu);
    // the cut that keeps the core forever out of reach
    float dwCut = max(dw, p.z - core_z);
    best.d = dwCut; best.mat = MAT_WALL; best.face = wface; best.tone = wu;
    best.suv = float2(wu, zs);

    // THE SHELL BOUND. Every rail, block and lamp lives within `shell` of the wall, and the bore
    // field is 1-Lipschitz, so a point further out than that is provably at least (dw - shell)
    // from all of them. Steps down the middle of the tube therefore cost ONE bore evaluation.
    float shell = 0.46 * pf.rin + 0.18;
    if (!full && dw > shell)
    {
        best.d = min(best.d, (dw - shell) * 0.85);
        return best;
    }

    float dr = max(railDist(p, pf, rail_amount), p.z - core_z);
    if (dr < best.d)
    {
        best.d = dr; best.mat = MAT_RAIL; best.face = wface; best.tone = wu;
        best.suv = float2(wu, zs);
    }

    // [loop] throughout: unrolling nine copies of the fixture field and six of the light field
    // into a function the marcher already calls per step turns a 2-second compile into minutes
    // and blows the instruction cache for no gain.
    int si = (int)floor(zs / RS_STATION_Z + 0.5);
    [loop] for (int o = -1; o <= 1; o++)
    {
        int sAbs = si + o;
        uint sIdx = (uint)rs_wrapI(sAbs);
        float zBase = (float)sAbs * RS_STATION_Z;

        [loop] for (uint k = 0u; k < RS_FIX_PER; k++)
        {
            RsRec r = Plan[RS_FIX_0 + sIdx * RS_FIX_PER + k];
            if (r.active < 0.5) continue;
            float zc = zBase + r.pos.x;
            if (abs(zs - zc) > r.phase + 0.45) continue;
            RsProfile fp = profileAt(zc);
            float d = max(fixDist(p, r, fp, zc, detail_amount), p.z - core_z);
            if (d < best.d)
            {
                best.d = d; best.mat = MAT_FIX; best.kind = (int)r.kind;
                best.tone = r.tone; best.face = (int)clamp(r.grp, 0.0, 2.0);
                // surface coordinates in the BLOCK's own frame, so its panelling runs with the
                // block rather than with the wall it happens to be sitting on
                RsFixGeo fg = rs_fixGeo(r, fp);
                best.suv = float2(dot(p.xy - fg.face, fg.tang), zs - zc);
            }
        }
        [loop] for (uint m = 0u; m < RS_LIGHT_PER; m++)
        {
            RsRec r = Plan[RS_LIGHT_0 + sIdx * RS_LIGHT_PER + m];
            if (r.active < 0.5) continue;
            float zc = zBase + r.pos.x;
            float reach = ((int)r.kind == LK_RUN) ? r.size.x : max(r.size.y, 0.05);
            if (abs(zs - zc) > reach + 0.35) continue;
            RsProfile lp = profileAt(zc);
            float d = max(lightDist(p, r, lp, zc), p.z - core_z);
            if (d < best.d)
            {
                best.d = d; best.mat = MAT_LIGHT; best.kind = (int)r.kind;
                best.tone = r.tone;
                best.emis = rs_lightCol(r, lp.pal) * r.tone;
            }
        }
    }
    return best;
}

float mapDist(float3 p) { return mapFull(p, false).d; }

float3 calcNormal(float3 p, float eps)
{
    float2 e = float2(1.0, -1.0) * eps;
    return normalize(e.xyy * mapDist(p + e.xyy) + e.yyx * mapDist(p + e.yyx)
                   + e.yxy * mapDist(p + e.yxy) + e.xxx * mapDist(p + e.xxx));
}

float calcAO(float3 p, float3 n, float reach)
{
    float occ = 0.0, sca = 1.0;
    [loop] for (int i = 0; i < 4; i++)
    {
        float h = 0.035 + 0.16 * (float)i * reach;
        occ += (h - mapDist(p + n * h)) * sca;
        sca *= 0.68;
    }
    return saturate(1.0 - 2.2 * occ);
}

// ---------------------------------------------------------------------------
// Wall / fixture surface. The records own the big readable structure; this owns the TEXTURE —
// the panel subdivision, the bolt lines and the scatter of small telltales that make the
// reference's walls read as dense machinery without needing a record per rivet.
// ---------------------------------------------------------------------------
// `pixWorld` is the world-space width of one pixel on this surface. Everything in here is
// procedural detail at a fixed world scale, so without it the panel grid on a wall seen at a
// grazing angle aliases into a uniform average of base and edge colour — which is exactly how a
// dark machined wall turns into a flat mid-grey sheet no matter what the lighting does.
float3 surfaceAlbedo(Hit h, float3 p, float3 n, RsProfile pf, float pixWorld,
                     out float3 emis, out float rough)
{
    float3 base = rs_pal(pf.pal, 0);
    float3 edge = rs_pal(pf.pal, 1);
    emis = float3(0.0, 0.0, 0.0);
    rough = 0.42;

    float zs = p.z + g_travel;

    if (h.mat == MAT_RAIL)
    {
        rough = 0.22;
        return lerp(base, edge, 0.42) * 1.15;
    }

    // Panel coordinates. Blocks get their own frame so their panelling runs WITH the block; the
    // wall gets (along-face, along-shaft). Same treatment either way, which is what makes a
    // block read as part of the same machine rather than an object dropped onto it.
    float cellU, cellV, mix, cellWorld;
    float3 c;
    if (h.mat == MAT_FIX)
    {
        cellWorld = 1.0 / 7.0;
        c = lerp(base, edge, 0.14 + h.tone * 0.34);
        if (h.kind == FK_FINS)   { c = lerp(c, edge, 0.20); rough = 0.30; }
        if (h.kind == FK_GRILLE) { c = lerp(c, edge, 0.30); rough = 0.26; }
        if (h.kind == FK_BEAM)   { c = lerp(c, base, 0.30); rough = 0.36; }
        if (h.kind == FK_DRUM)   { rough = 0.18; }
        cellU = h.suv.x * 7.0;
        cellV = h.suv.y * 7.0;
        mix = (float)h.kind * 11.0 + 3.0;
        c *= 0.80 + 0.50 * h.tone;
    }
    else
    {
        // must match wallDist exactly, or the paint sits somewhere other than the relief
        float ps = RS_PANEL_Z;
        float lat = 4.2 / max(pf.panel, 0.15);
        cellU = h.suv.x * lat;
        cellV = rs_wrapZ(h.suv.y) / ps;
        mix = (float)h.face * 31.0;
        cellWorld = min(pf.rin / lat, ps);
        c = base;
    }

    float3 flat_ = c;
    // 0 when one pixel spans a panel or more, 1 when the panel is comfortably resolved. The
    // per-cell hash cannot be filtered analytically, so this is where it gives up.
    float fade = smoothstep(1.30, 0.30, pixWorld / max(cellWorld, 1e-4));

    float2 pc = float2(cellU, cellV);
    float2 cell = floor(pc);
    float2 f = frac(pc);
    float2 rh = rs_hash22(cell + mix);

    // Panel-to-panel variation is deliberately narrow. A wide range turns a machined wall into a
    // checkerboard, which is the read a per-cell hash falls into by default and the one thing
    // that most obviously says "procedural" about a surface like this.
    c *= lerp(0.86, 1.16, rh.x);
    // recessed panels read darker; a few are proud and catch the edge colour
    if (rh.y > 0.90) c = lerp(c, edge, 0.16);
    else if (rh.y < 0.16) c *= 0.74;

    // Bevel lines between panels, ANALYTICALLY WIDENED to one pixel. A fixed-width line at a
    // fixed world scale is the single worst aliaser in a scene like this: at distance it lands
    // between samples and the wall breaks into moire stripes that the bloom then amplifies into
    // a shimmering mess. Growing the filter with the pixel footprint is the actual fix; fading
    // the whole material out only trades stripes for mush.
    float pwc = pixWorld / max(cellWorld, 1e-4);         // pixel width in cell units
    float2 gl = min(f, 1.0 - f);
    float g = min(gl.x, gl.y);
    c = lerp(c, edge, (1.0 - smoothstep(0.0, 0.05 + pwc * 1.6, g)) * 0.34 * panel_edge);
    c *= lerp(1.0, 0.42, 1.0 - smoothstep(0.0, 0.013 + pwc * 1.6, g));

    // a rib texture inside some panels, which is what makes a surface read as fabricated. Its
    // frequency is several times the panel's, so it has to give up several times sooner.
    if (rh.x > 0.50)
    {
        float rf = lerp(4.0, 12.0, rh.y);
        float ribFade = saturate(1.0 - pwc * rf * 2.2);
        float rib = abs(frac(f.y * rf) - 0.5) * 2.0;
        c *= lerp(1.0, lerp(0.78, 1.18, smoothstep(0.35, 0.65, rib)), ribFade);
    }

    // TELLTALES. These must be small marks INSIDE a panel, not the panel itself — lighting a
    // whole cell turns every one into a window and the wall stops being machinery.
    // Sparse on purpose. An earlier pass lit about a fifth of all cells and the wall stopped
    // reading as a dark machine with lights on it and started reading as a light-up toy — the
    // reference has a handful of very bright sources and a great deal of darkness.
    float2 fc = f - 0.5;
    if (rh.x > 0.975)
    {
        // a short strip light recessed into the panel
        float strip = step(abs(fc.x), 0.30) * step(abs(fc.y), 0.055);
        emis += float3(0.82, 0.94, 1.00) * telltale_gain * strip;
    }
    else if (rh.x < 0.020)
    {
        float dot2 = step(max(abs(fc.x), abs(fc.y)), 0.075);
        emis += lerp(RS_BEACON_A, RS_BEACON_B, rh.y) * telltale_gain * 1.4 * dot2;
    }
    else if (rh.y > 0.986)
    {
        // a run of tiny indicator pips
        float pip = step(abs(frac(fc.x * 5.0) - 0.5), 0.16) * step(abs(fc.y - 0.30), 0.045);
        emis += rs_pal(pf.pal, 2) * telltale_gain * 0.9 * pip;
    }
    // unresolved telltales would strobe as the shaft scrolls; fading them keeps the distance
    // quiet, which is also what the reference does — the far machinery is dark, not sparkly
    emis *= fade * fade;

    // These are matte machine panels, not mirrors. Letting roughness reach 0.26 gave a broad
    // specular lobe that a nearby tube could paint across an entire flat wall in one saturated
    // sheet — a lighting bug that looks exactly like a colour-grading mistake.
    rough = lerp(0.80, 0.50, rh.x);
    return lerp(flat_ * 0.82, c, fade);
}

// ---------------------------------------------------------------------------
// Light gathering. The core is a POSITION just past the cut, so light arrives ALONG the shaft
// and the throat is bright while the foreground falls away — which is the reference's whole
// depth read. The neon adds local colour where it actually is.
// ---------------------------------------------------------------------------
float3 gatherLights(float3 p, float3 n, float3 v, float3 albedo, float rough)
{
    float3 lit = float3(0.0, 0.0, 0.0);
    float zs = p.z + g_travel;

    // --- key: the core
    float3 cpos = float3(Plan[RS_CORE].pos * 0.5, core_z + 1.2);
    float3 ld = cpos - p;
    float dist = length(ld);
    ld /= max(dist, 1e-4);
    float3 keyCol = lerp(RS_CORE_RED, RS_CORE_HOT, 0.45) * Plan[RS_CORE].tone;
    // A steep quadratic falloff is what produces the reference's read: a blazing throat and a
    // foreground that drops into near-black. A gentle one lights the whole tube evenly and the
    // depth disappears.
    float atten = 1.0 / (1.0 + dist * dist * 0.014);
    float ndl = saturate(dot(n, ld));
    // walls run nearly parallel to the key, so a plain lambert blacks them out; a wrapped term
    // keeps them shaped instead of dead
    float wrapd = saturate((dot(n, ld) + 0.45) / 1.45);
    lit += albedo * keyCol * key_gain * atten * lerp(wrapd, ndl, 0.45);

    // Normalized Blinn: without the (shininess+8)/8 term a smooth surface at a grazing angle
    // returns a highlight of area ~1 and the whole wall goes white.
    float3 hv = normalize(ld + v);
    float sh = lerp(8.0, 160.0, 1.0 - rough);
    float specN = (sh + 8.0) / 128.0;
    lit += keyCol * key_gain * atten * spec_gain * specN
         * pow(saturate(dot(n, hv)), sh) * (1.0 - rough) * ndl;

    // --- the neon in this station window
    int si = (int)floor(zs / RS_STATION_Z + 0.5);
    [loop] for (int o = -1; o <= 1; o++)
    {
        uint sIdx = (uint)rs_wrapI(si + o);
        RsProfile lp = profileAt((float)(si + o) * RS_STATION_Z);
        [loop] for (uint m = 0u; m < RS_LIGHT_PER; m++)
        {
            RsRec r = Plan[RS_LIGHT_0 + sIdx * RS_LIGHT_PER + m];
            if (r.active < 0.5) continue;
            float2 tg;
            float2 sp = rs_lightSection(r, lp, tg);
            float3 lp3 = float3(sp, (float)(si + o) * RS_STATION_Z + r.pos.x - g_travel);
            float3 dl = lp3 - p;
            float dd = length(dl);
            if (dd > neon_reach) continue;
            dl /= max(dd, 1e-4);
            float3 lc = rs_lightCol(r, lp.pal) * r.tone;
            float fall = 1.0 / (1.0 + dd * dd * 2.4 / max(neon_reach, 0.1));
            float nl = saturate(dot(n, dl) * 0.72 + 0.28);
            lit += albedo * lc * neon_gain * fall * nl;
            float3 h2 = normalize(dl + v);
            float sh2 = lerp(8.0, 120.0, 1.0 - rough);
            lit += lc * neon_gain * fall * spec_gain * ((sh2 + 8.0) / 128.0) * 0.5
                 * pow(saturate(dot(n, h2)), sh2) * (1.0 - rough) * saturate(dot(n, dl));
        }
    }
    return lit;
}

// ---------------------------------------------------------------------------
// Volume. The reference is at least half atmosphere: teal in the near air, magenta down by the
// core, and a bloom of colour around every tube. Integrated along the ray rather than applied
// as a flat depth fade, so the light actually sits in the air where the lamps are.
// ---------------------------------------------------------------------------
// Returns in-scattered radiance and, through `trans`, the transmittance the surface behind it
// survives with. Integrating WITHOUT transmittance is what turns a shaft into a pink fog bank:
// the haze then adds to everything equally instead of progressively hiding it, and the whole
// image lifts off black at once.
float3 marchVolume(float3 ro, float3 rd, float tMax, float jitter, out float trans)
{
    int steps = max((int)volume_steps, 1);
    float3 acc = float3(0.0, 0.0, 0.0);
    float T = 1.0;
    float tEnd = min(tMax, core_z + 4.0);
    float dt = tEnd / (float)steps;

    [loop] for (int i = 0; i < steps; i++)
    {
        float t = ((float)i + jitter) * dt;
        float3 p = ro + rd * t;
        float zs = p.z + g_travel;

        float depth = saturate(p.z / max(core_z, 1.0));
        float sigma = fog_density * (0.55 + 1.20 * depth);
        float3 inscat = lerp(RS_HAZE_NEAR, RS_HAZE_DEEP, depth * depth);

        // the core's wash, which is what fills the deep end with magenta
        float dc = length(float3(0.0, 0.0, core_z + 1.2) - p);
        inscat += lerp(RS_CORE_RED, RS_HAZE_DEEP, 0.45) * Plan[RS_CORE].tone
                * core_wash / (1.0 + dc * dc * 0.020);

        // scattering from the neon nearby — the halo of colour in the air around every tube
        int si = (int)floor(zs / RS_STATION_Z + 0.5);
        [loop] for (int o = -1; o <= 1; o++)
        {
            uint sIdx = (uint)rs_wrapI(si + o);
            RsProfile lp = profileAt((float)(si + o) * RS_STATION_Z);
            [loop] for (uint m = 0u; m < RS_LIGHT_PER; m++)
            {
                RsRec r = Plan[RS_LIGHT_0 + sIdx * RS_LIGHT_PER + m];
                if (r.active < 0.5) continue;
                float2 tg;
                float2 sp = rs_lightSection(r, lp, tg);
                float3 lp3 = float3(sp, (float)(si + o) * RS_STATION_Z + r.pos.x - g_travel);
                float dd2 = dot(lp3 - p, lp3 - p);
                inscat += rs_lightCol(r, lp.pal) * r.tone * glow_gain / (1.0 + dd2 * 6.0);
            }
        }

        acc += T * inscat * sigma * dt;
        T *= exp(-sigma * dt);
    }
    trans = T;
    return acc;
}

// One primary ray, start to finish. Kept as a function so the antialiasing loop is nine CALLS
// rather than nine inlined copies of the renderer.
float3 renderSample(float3 ro, float3 rd, float jitter, out float tOut)
{
    float t = 0.02;
    float tMax = core_z + 6.0;
    int steps = clamp((int)march_steps, 24, 320);
    bool hitSurf = false;
    float eps = max(surface_eps, 0.0002);
    int taken = 0;

    [loop] for (int i = 0; i < steps; i++)
    {
        float3 p = ro + rd * t;
        float d = mapDist(p);
        taken = i;
        if (d < eps * max(t, 1.0)) { hitSurf = true; break; }
        if (t > tMax) break;
        t += max(d * step_scale, eps * 0.5);
    }

    float3 col = float3(0.0, 0.0, 0.0);
    float tHit = min(t, tMax);
    float3 nOut = float3(0.0, 0.0, 1.0);
    float matOut = 0.0;

    if (hitSurf)
    {
        float3 p = ro + rd * t;
        Hit h = mapFull(p, true);
        RsProfile pf = profileAt(p.z + g_travel);
        float3 n = calcNormal(p, max(normal_eps, 0.0004));
        float3 v = -rd;
        nOut = n;
        matOut = (float)h.mat / 4.0;

        if (h.mat == MAT_LIGHT)
        {
            // emitters are emitters: they go out hot so the lens has something to bloom
            float fres = pow(1.0 - saturate(dot(n, v)), 1.6);
            col = h.emis * emitter_gain * (0.85 + 1.5 * fres);
        }
        else
        {
            float nv = max(abs(dot(n, v)), 0.06);
            float pixWorld = t * 2.0 * tan(_CameraFOV * 0.008726646)
                           / max(_Resolution.y, 1.0) / nv;

            float3 emis; float rough;
            float3 alb = surfaceAlbedo(h, p, n, pf, pixWorld, emis, rough);
            float ao = lerp(1.0, calcAO(p, n, ao_reach), ao_amt);
            float depth01 = saturate(p.z / max(core_z, 1.0));
            float3 airCol = lerp(RS_HAZE_NEAR, RS_HAZE_DEEP, depth01 * depth01);

            col = gatherLights(p, n, v, alb, rough) * ao;
            // Cold fill. This is the only light the near structure gets in quantity, and it is
            // deliberately teal: the reference's foreground is cool and the warmth is confined
            // to the throat and to the tubes themselves.
            col += alb * airCol * 3.0 * ambient * ao;

            // COLD RIM. Every panel edge and every silhouette in the reference carries a thin
            // cool highlight; it is what separates one dark block from the dark block behind it.
            //
            // Gated on real CONVEXITY, not on fresnel alone. A tunnel wall is seen at a grazing
            // angle over its entire area, so a plain fresnel rim floods the whole wall and turns
            // the machinery into a pale sheet. Stepping one epsilon along the normal and asking
            // the field how far it got is a true convexity measure: flat returns the step, a
            // convex edge returns less.
            // The threshold is the whole point. With micro-relief on, SOME convexity exists at
            // nearly every pixel, so an ungated measure lights the entire wall and flattens the
            // image exactly the way a plain fresnel does. Only a genuine edge should fire.
            float ek = max(normal_eps * 6.0, 0.01);
            float curv = saturate(((ek - mapDist(p + n * ek)) / ek - 0.34) * 3.4);
            float fres = pow(1.0 - saturate(dot(n, v)), 2.0);
            col += lerp(RS_FLOOD_COL, airCol * 3.0, depth01) * rim_gain
                 * lerp(fres * 0.18, 1.0, curv) * (0.30 + 0.70 * ao);
            col += emis;
        }
    }
    else
    {
        // the ray got past the cut: show the core through the hole
        float tp = (core_z - ro.z) / max(rd.z, 1e-4);
        if (tp > 0.0 && rd.z > 0.0)
        {
            float3 pp = ro + rd * tp;
            RsProfile pf = profileAt(core_z + g_travel);
            float2 s = (pp.xy - pf.c) / max(pf.rin, 1e-3);
            col = rs_corePlate(s, Plan[RS_CORE], _Time * Plan[RS_CORE].phase, 0.004);
            tHit = tp;
        }
    }

    float trans;
    float3 vol = marchVolume(ro, rd, tHit, jitter, trans);
    col = col * trans + vol;

    int vm = (int)view_mode;
    if (vm == 1)      col = float3(matOut, 0.30, 0.60);
    else if (vm == 2) col = float3((float)taken / (float)steps, 0.20, 0.60);
    else if (vm == 3) col = hitSurf ? (nOut * 0.5 + 0.5) : float3(0.0, 0.0, 0.0);
    else if (vm == 4) col = saturate(tHit / max(core_z, 1.0)).xxx;

    tOut = tHit;
    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (pixel.x >= W || pixel.y >= H) return;

    RsRec hdr = Plan[RS_HEADER];
    g_travel = hdr.phase;
    g_style = (int)floor(hdr.flags / 262144.0);

    int aa = clamp((int)aa_samples, 1, 3);
    float3 sum = float3(0.0, 0.0, 0.0);
    float depthOut = core_z + 8.0;

    [loop] for (int sy = 0; sy < aa; sy++)
    [loop] for (int sx = 0; sx < aa; sx++)
    {
        float2 jit = (aa == 1) ? float2(0.5, 0.5)
                               : (float2((float)sx, (float)sy) + 0.5) / (float)aa;
        float2 screenUV = ((float2)pixel + jit) / float2(W, H);
        float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

        float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
        nearW /= nearW.w;
        farW  /= farW.w;
        float3 ro = _CameraPos;
        float3 rd = normalize(farW.xyz - nearW.xyz);

        float jitter = frac(sin(dot((float2)pixel + (float)(sy * 3 + sx) * 17.0,
                                    float2(12.9898, 78.233))) * 43758.5453);
        float tHit;
        sum += renderSample(ro, rd, jitter, tHit);
        if (sx == 0 && sy == 0) depthOut = tHit;
    }

    float3 outCol = sum / (float)(aa * aa) * exposure;
    // RGBA16F with LINEAR DEPTH IN ALPHA — the lens downstream needs real depth, and a
    // tonemapped 8-bit hand-off would throw away every highlight the bloom is made of.
    OutputUAV[pixel] = float4(outCol, depthOut);
}
