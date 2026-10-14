// br_scene.hlsli -- the room as a signed distance field, in REST space (before any trip warp).
//
// Everything here is read from BR_Render's `scene` buffer (prep.hlsl normalises the Shell /
// Finish / Furnish / Light / Trip / Rug inputs into it), declared by the including pass as
//     StructuredBuffer<BRRec> SceneBuf : register(t0);
//
// Two maps:
//   sceneMap(q)  -- everything opaque: the wall/floor/ceiling slabs with their openings cut,
//                   window frames and sashes, casings, stools, radiators, trims, door, fireplace,
//                   furniture.
//   veilMap(q)   -- the translucent layer: glass panes and sheer curtains. Kept OUT of sceneMap so
//                   a primary ray never stops on glass; the shade pass composites it.
//
// Sizes are real: a 30 cm masonry wall with the window set 7.5 cm from the street face (so the
// reveal is deep and catches light), 5 cm sash members, 18 mm muntins, a 13 cm cove crown, a
// cast-iron column radiator at 63.5 mm pitch.
#ifndef BR_SCENE_HLSLI
#define BR_SCENE_HLSLI

#include "../_shared/br_records.hlsli"
#include "../_shared/br_sdf.hlsli"

// --- BR_Render scene buffer layout --------------------------------------------------------------
#define SC_ROOM      0
#define SC_OPEN0     1      // 8 openings
#define SC_SUN       9      // dims: sunDir.xyz, sunI   look: sunRad.rgb, softness   meta: skyI, wind, canopy, time
#define SC_FRAME     10     // dims: frame, jitter.xy, staticFrames   look: camera motion, warp motion, dt, time
#define SC_VP_PREV   11     // 4 rows
#define SC_VP_CUR    15     // 4 rows
#define SC_COUNTS    19     // dims: objects, lamps, anchors, rugLinked
#define SC_LAMP0     20     // 12 lamps
#define SC_LAMP_MAX  12
#define SC_TRIP      32     // trip globals
#define SC_ANCH0     33     // 15 anchors
#define SC_ANCH_MAX  15
#define SC_RUG       48     // 8 rug design records
#define SC_IVP_CUR   56     // 4 rows: inverse view-projection this frame (BR_Lens reprojection)
#define SC_CAM       60     // dims: the eye this frame
#define SC_OBJ0      64     // 64 render objects (BR_Furnish publishes at most 48)
#define SC_OBJ_MAX   64
#define SC_OWARP0    128    // per object: its trip warp this frame, parallel to SC_OBJ0 (prep.hlsl)
                            //   head (breathe amp, breathe rate Hz, breathe phase, slump)  dims (twist, reach, 0, 0)
#define SC_MAT0      192    // 24 material records (Finish, or the house defaults)
#define SC_RECORDS   224

// part ids for shading decisions (encoded alongside the material slot)
#define PART_SHELL     0
#define PART_FLOOR     1
#define PART_CEILING   2
#define PART_REVEAL    3
#define PART_TRIM      4
#define PART_CASING    5
#define PART_STOOL     6
#define PART_FRAME     7
#define PART_SASH      8
#define PART_MUNTIN    9
#define PART_RADIATOR  10
#define PART_ROD       11
#define PART_DOOR      12
#define PART_KNOB      13
#define PART_BREAST    14
#define PART_SURROUND  15
#define PART_MANTEL    16
#define PART_FIREBOX   17
#define PART_HEARTH    18
#define PART_GLASS     19
#define PART_SHEER     20
#define PART_FURN      32     // furniture parts start here

BRRoom scRoom() { return brRoomFromRec(SceneBuf[SC_ROOM]); }
BROpening scOpen(int i) { return brOpeningFromRec(SceneBuf[SC_OPEN0 + i]); }

// Wall-local coordinates of q for an opening: x along the wall from the opening centre (world
// axis direction), y above the sill, z = distance INTO the room from the interior face.
float3 openLocal(float3 q, BROpening o, BRRoom R)
{
    float along = brWallAlongX(o.wall) ? q.x : q.z;
    float plane = brWallPlane(R, o.wall);
    float2 n = brWallNormal(o.wall);
    float d = brWallAlongX(o.wall) ? (q.z - plane) * n.y : (q.x - plane) * n.x;
    return float3(along - o.a, q.y - o.sill, d);
}

// The cut through the wall for an opening (arch = box + half-disc head).
float openingHole(float3 lq, BROpening o, float T)
{
    float hw = o.width * 0.5;
    float dz = abs(lq.z + T * 0.5) - (T * 0.5 + 0.06);
    if (o.kind == OPEN_ARCH)
    {
        float cy = o.height - hw;
        float2 uv = float2(lq.x, lq.y - cy);
        float s2 = min(length(uv) - hw, sdBox2(float2(lq.x, lq.y - cy * 0.5 + 0.03), float2(hw, cy * 0.5 + 0.03)));
        return max(s2, dz);
    }
    float2 b = float2(hw, o.height * 0.5);
    float s = sdBox2(float2(lq.x, lq.y - o.height * 0.5), b);
    return max(s, dz);
}

// Frame + sashes + muntins of a glazed opening, in opening-local coordinates.
void windowFrame(float3 lq, BROpening o, float T, inout SHit h, int slot)
{
    float hw = o.width * 0.5;
    float hgt = o.height;
    float dc = -T + 0.075;                         // frame centre depth (from interior face)
    float fw = 0.052;                              // frame member width
    // outer frame ring
    float outerF = sdAabb(lq, float3(-hw, 0.0, dc - 0.045), float3(hw, hgt, dc + 0.045));
    float innerF = sdAabb(lq, float3(-hw + fw, fw, dc - 0.06), float3(hw - fw, hgt - fw, dc + 0.06));
    hmin(h, max(outerF, -innerF), MAT_WINDOW, PART_FRAME, -1 - slot);
    float2 lo = float2(-hw + fw, fw), hi = float2(hw - fw, hgt - fw);
    if (o.kind == OPEN_DOUBLEHUNG)
    {
        float mid = (lo.y + hi.y) * 0.5;
        // lower sash (room side), upper sash (street side), overlapping at the meeting rail
        [unroll] for (int s = 0; s < 2; s++)
        {
            float y0 = (s == 0) ? lo.y : mid - 0.022;
            float y1 = (s == 0) ? mid + 0.022 : hi.y;
            float zc = (s == 0) ? dc + 0.024 : dc - 0.024;
            float so = sdRAabb(lq, float3(lo.x, y0, zc - 0.021), float3(hi.x, y1, zc + 0.021), 0.004);
            float bot = (s == 0) ? 0.075 : 0.045;
            float si = sdAabb(lq, float3(lo.x + 0.046, y0 + bot, zc - 0.04), float3(hi.x - 0.046, y1 - 0.045, zc + 0.04));
            hmin(h, max(so, -si), MAT_WINDOW, PART_SASH, -1 - slot);
            // muntins: (cols-1) verticals through the glazing
            float cols = max(o.cols, 1.0);
            float gx0 = lo.x + 0.046, gx1 = hi.x - 0.046;
            float pitch = (gx1 - gx0) / cols;
            float k = clamp(round((lq.x - gx0) / pitch), 1.0, max(cols - 1.0, 1.0));
            float mx = gx0 + k * pitch;
            if (cols > 1.5)
            {
                float m = sdRAabb(lq, float3(mx - 0.009, y0 + bot, zc - 0.012), float3(mx + 0.009, y1 - 0.045, zc + 0.012), 0.003);
                hmin(h, m, MAT_WINDOW, PART_MUNTIN, -1 - slot);
            }
        }
        return;
    }
    // casement / picture / french: leaves split by mullions, lights split by transoms
    float cols = (o.kind == OPEN_PICTURE) ? 1.0 : max(o.cols, 1.0);
    float rows = max(o.rows, 1.0);
    float y0 = lo.y;
    if (o.kind == OPEN_FRENCH)
    {
        // kick panels at the bottom of each leaf
        float kp = sdRAabb(lq, float3(lo.x, 0.0, dc - 0.022), float3(hi.x, 0.36, dc + 0.022), 0.004);
        hmin(h, kp, MAT_WINDOW, PART_SASH, -1 - slot);
        y0 = 0.36;
    }
    float leafPitch = (hi.x - lo.x) / cols;
    float kx = clamp(round((lq.x - lo.x) / leafPitch), 1.0, max(cols - 1.0, 1.0));
    float mullX = lo.x + kx * leafPitch;
    if (cols > 1.5)
    {
        float mm = sdRAabb(lq, float3(mullX - 0.024, y0, dc - 0.03), float3(mullX + 0.024, hi.y, dc + 0.03), 0.004);
        hmin(h, mm, MAT_WINDOW, PART_SASH, -1 - slot);
    }
    if (rows > 1.5)
    {
        float rp = (hi.y - y0) / rows;
        float ky = clamp(round((lq.y - y0) / rp), 1.0, max(rows - 1.0, 1.0));
        float ty = y0 + ky * rp;
        float tm = sdRAabb(lq, float3(lo.x, ty - 0.011, dc - 0.014), float3(hi.x, ty + 0.011, dc + 0.014), 0.003);
        hmin(h, tm, MAT_WINDOW, PART_MUNTIN, -1 - slot);
    }
}

// Interior trim of an opening: casing legs + head, stool + apron for windows.
void openingTrim(float3 lq, BROpening o, float T, inout SHit h, int slot)
{
    float hw = o.width * 0.5;
    float cw = 0.075;
    if (o.kind == OPEN_FIREPLACE) return;
    float headTop = o.height + cw;
    float legs = min(sdRAabb(lq, float3(-hw - cw, 0.0, -0.002), float3(-hw, headTop, 0.020), 0.003),
                     sdRAabb(lq, float3(hw, 0.0, -0.002), float3(hw + cw, headTop, 0.020), 0.003));
    float head = sdRAabb(lq, float3(-hw - cw - 0.012, o.height, -0.002), float3(hw + cw + 0.012, headTop + 0.018, 0.027), 0.004);
    if (o.kind == OPEN_ARCH)
    {
        // an arch gets an archivolt band following the curve
        float cy = o.height - hw;
        float2 uv = float2(lq.x, lq.y - cy);
        float band = abs(length(uv) - hw - cw * 0.5) - cw * 0.5;
        float arc = max(max(band, -uv.y), abs(lq.z - 0.009) - 0.011);
        float legA = min(sdRAabb(lq, float3(-hw - cw, 0.0, -0.002), float3(-hw, cy, 0.020), 0.003),
                         sdRAabb(lq, float3(hw, 0.0, -0.002), float3(hw + cw, cy, 0.020), 0.003));
        hmin(h, min(arc, legA), MAT_TRIM, PART_CASING, -1 - slot);
        return;
    }
    hmin(h, min(legs, head), (o.kind == OPEN_DOOR) ? MAT_DOOR : MAT_TRIM, PART_CASING, -1 - slot);
    if (brOpenIsWindow(o.kind))
    {
        float stool = sdRAabb(lq, float3(-hw - cw - 0.035, -0.032, -T + 0.12), float3(hw + cw + 0.035, 0.0, 0.048), 0.005);
        float apron = sdRAabb(lq, float3(-hw - cw + 0.02, -0.135, -0.002), float3(hw + cw - 0.02, -0.032, 0.019), 0.003);
        hmin(h, min(stool, apron), MAT_TRIM, PART_STOOL, -1 - slot);
    }
}

// Cast-iron column radiator under a window: rounded columns at 63.5 mm pitch, top and bottom
// manifolds, two feet and a valve.
void radiator(float3 lq, BROpening o, inout SHit h, int slot)
{
    float hw = o.width * 0.5 - 0.06;
    float yb = 0.11 - o.sill, yt = min(-0.14, 0.74 - o.sill);
    if (yt - yb < 0.18) return;
    float3 c = float3(0.0, (yb + yt) * 0.5, 0.105);
    float bound = sdAabb(lq, float3(-hw - 0.02, yb - 0.12, 0.03), float3(hw + 0.02, yt + 0.02, 0.18));
    if (bound > 0.08) { hmin(h, bound, MAT_IRON, PART_RADIATOR, -1 - slot); return; }   // conservative
    float pitch = 0.0635;
    float n = floor(hw / pitch);
    float k = clamp(round(lq.x / pitch), -n, n);
    float3 p = lq - float3(k * pitch, 0, 0);
    float halfH = (yt - yb) * 0.5;
    float col = sdRAabb(p, float3(-0.022, yb + 0.03, 0.040), float3(0.022, yt - 0.03, 0.170), 0.018);
    float waist = sdAabb(p, float3(-0.03, yb + 0.09, 0.085), float3(0.03, yt - 0.09, 0.125));
    col = max(col, -waist);   // the slot between the two tubes of each column
    float manifold = min(sdRAabb(lq, float3(-n * pitch - 0.02, yt - 0.06, 0.05), float3(n * pitch + 0.02, yt - 0.01, 0.16), 0.02),
                         sdRAabb(lq, float3(-n * pitch - 0.02, yb + 0.01, 0.05), float3(n * pitch + 0.02, yb + 0.06, 0.16), 0.02));
    float feet = min(sdRAabb(lq, float3(-n * pitch - 0.01, yb - 0.11 + 0.0, 0.07), float3(-n * pitch + 0.035, yb + 0.02, 0.14), 0.006),
                     sdRAabb(lq, float3(n * pitch - 0.035, yb - 0.11, 0.07), float3(n * pitch + 0.01, yb + 0.02, 0.14), 0.006));
    float valve = sdCapsuleSeg(lq, float3(n * pitch + 0.06, yb - 0.11, 0.11), float3(n * pitch + 0.06, yb + 0.05, 0.11), 0.012);
    float rad = min(min(col, manifold), min(feet, valve));
    hmin(h, rad, MAT_IRON, PART_RADIATOR, -1 - slot);
}

void curtainRod(float3 lq, BROpening o, inout SHit h, int slot)
{
    float hw = o.width * 0.5;
    float y = o.height + 0.17;
    float ext = hw + 0.38;
    float rod = sdCapsuleSeg(lq, float3(-ext, y, 0.115), float3(ext, y, 0.115), 0.011);
    float fin = min(length(lq - float3(-ext - 0.03, y, 0.115)) - 0.026, length(lq - float3(ext + 0.03, y, 0.115)) - 0.026);
    float br = min(sdRAabb(lq, float3(-ext + 0.06, y - 0.012, 0.0), float3(-ext + 0.085, y + 0.012, 0.115), 0.004),
                   sdRAabb(lq, float3(ext - 0.085, y - 0.012, 0.0), float3(ext - 0.06, y + 0.012, 0.115), 0.004));
    hmin(h, min(min(rod, fin), br), MAT_BRASS, PART_ROD, -1 - slot);
}

void doorLeaf(float3 lq, BROpening o, inout SHit h, int slot)
{
    float hw = o.width * 0.5;
    float leaf = sdRAabb(lq, float3(-hw + 0.003, 0.006, -0.052), float3(hw - 0.003, o.height - 0.003, -0.010), 0.004);
    // recessed panels (cols x rows): stiles 0.11, rails 0.11/0.2/0.25
    float cols = max(o.cols, 1.0);
    float m = 0.11;
    float pw = (o.width - 2.0 * m - (cols - 1.0) * 0.09) / cols;
    float kx = clamp(floor((lq.x + hw - m) / (pw + 0.09)), 0.0, cols - 1.0);
    float px0 = -hw + m + kx * (pw + 0.09);
    float rowsY[4] = { 0.20, 0.82, 1.06, o.height - 0.11 };
    float ky = (lq.y < 0.94) ? 0.0 : 1.0;
    float py0 = (ky < 0.5) ? rowsY[0] : rowsY[2];
    float py1 = (ky < 0.5) ? rowsY[1] : rowsY[3];
    float recess = sdAabb(lq, float3(px0, py0, -0.022), float3(px0 + pw, py1, 0.01));
    float raised = sdRAabb(lq, float3(px0 + 0.04, py0 + 0.04, -0.03), float3(px0 + pw - 0.04, py1 - 0.04, -0.013), 0.01);
    float door = min(max(leaf, -recess), raised);
    hmin(h, door, MAT_DOOR, PART_DOOR, -1 - slot);
    float3 kp = lq - float3(hw - 0.075, 0.97, 0.0);
    float knob = min(length(kp - float3(0, 0, 0.055)) - 0.027, sdCapsuleSeg(kp, float3(0, 0, -0.01), float3(0, 0, 0.045), 0.009));
    float rose = sdRCylY(float3(kp.x, kp.z + 0.004, kp.y), 0.006, 0.026, 0.003);
    hmin(h, min(knob, rose), MAT_BRASS, PART_KNOB, -1 - slot);
}

// Chimney breast + marble surround + firebox + hearth. Contributes to the SOLID (breast) and
// to the cut (firebox) of the shell, so it returns the breast union and the cavity separately.
void fireplace(float3 lq, BROpening o, BRRoom R, inout float solidAdd, inout float cavity, inout float breastOut, inout SHit h, int slot)
{
    float hw = o.width * 0.5;
    float dep = o.depth;
    float mh = o.height;
    float breast = sdAabb(lq, float3(-hw, -0.05, -0.05), float3(hw, R.H + 0.05, dep));
    solidAdd = min(solidAdd, breast);
    float fbw = o.cols * 0.5, fbh = o.rows;
    float capH = fbw * 0.55;
    float cy = fbh - capH;
    float2 uv = float2(lq.x, lq.y - cy);
    float cap = (length(float2(uv.x / fbw, max(uv.y, 0.0) / capH)) - 1.0) * capH;
    float box2 = min(cap, sdBox2(float2(lq.x, lq.y - (cy + 0.02) * 0.5), float2(fbw, (cy + 0.02) * 0.5 + 0.02)));
    float fb = max(box2, abs(lq.z - (dep - 0.21)) - 0.215);
    cavity = min(cavity, fb);
    // The breast is opened by a cut that runs 20 cm PAST its front face. A cut that stops a few
    // millimetres beyond the face leaves a sliver of near-zero distance across the whole mouth,
    // and the march lands on it: the firebox reads as a painted panel.
    float mouth = max(box2, abs(lq.z - (dep - 0.21 + 0.10)) - 0.315);
    float bo = max(breast, -mouth);
    // the firebox walls are the breast's own cut faces: deep inside the breast they are sooted
    // firebrick, not plaster (only the last few mm at the mouth stay wall)
    bool inBox = breast < -0.006;
    hmin(h, bo, inBox ? MAT_BLACKMETAL : MAT_WALL, inBox ? PART_FIREBOX : PART_BREAST, -1);
    breastOut = min(breastOut, 1e9);
    // marble surround: pilasters, frieze, shelf
    float pil = min(sdRAabb(lq, float3(-hw + 0.05, 0.0, dep - 0.01), float3(-hw + 0.28, mh - 0.10, dep + 0.038), 0.006),
                    sdRAabb(lq, float3(hw - 0.28, 0.0, dep - 0.01), float3(hw - 0.05, mh - 0.10, dep + 0.038), 0.006));
    float frieze = sdRAabb(lq, float3(-hw + 0.05, mh - 0.30, dep - 0.01), float3(hw - 0.05, mh - 0.08, dep + 0.030), 0.005);
    float slips = sdAabb(lq, float3(-fbw - 0.10, 0.0, dep - 0.01), float3(fbw + 0.10, fbh + 0.10, dep + 0.012));
    // the surround is cut by a deeper version of the opening, so no marble film is left over it
    float fbS = max(box2, abs(lq.z - (dep - 0.10)) - 0.26);
    float surround = max(min(min(pil, frieze), slips), -fbS);
    hmin(h, surround, MAT_STONE, PART_SURROUND, -1 - slot);
    float shelf = sdRAabb(lq, float3(-hw - 0.06, mh - 0.085, dep - 0.02), float3(hw + 0.06, mh, dep + 0.16), 0.012);
    float shelfCap = sdRAabb(lq, float3(-hw - 0.04, mh - 0.115, dep - 0.02), float3(hw + 0.04, mh - 0.08, dep + 0.12), 0.01);
    hmin(h, min(shelf, shelfCap), MAT_STONE, PART_MANTEL, -1 - slot);
    float hearth = sdRAabb(lq, float3(-hw - 0.12, -0.02, dep - 0.42), float3(hw + 0.12, 0.035, dep + 0.48), 0.006);
    // the inner hearth (inside the firebox) is firebrick; the outer hearth is the marble slab
    bool inner = lq.z < dep - 0.012 && abs(lq.x) < fbw + 0.01;
    hmin(h, hearth, inner ? MAT_BLACKMETAL : MAT_STONE, inner ? PART_FIREBOX : PART_HEARTH, inner ? -1 : -1 - slot);
}

// Baseboard, picture rail and cove crown along one wall, as 2D profiles in (d, y) extruded along
// the wall. `casingCut` removes them where an opening's casing sits.
float wallTrims(float3 q, int w, BRRoom R)
{
    float plane = brWallPlane(R, w);
    float2 n = brWallNormal(w);
    float d = brWallAlongX(w) ? (q.z - plane) * n.y : (q.x - plane) * n.x;
    // every trim lies within `reach` of the wall, so farther out d - reach is a safe LOWER bound.
    // Never return "infinitely far" here: a ray heading for the cornice then steps clean through
    // it and lands inside the moulding at a random depth -- the crown rendered as noisy slots
    // wherever no furniture bound happened to shorten the steps.
    float reach = max(R.crown + 0.025, 0.04);
    if (d > reach + 0.05) return d - reach;
    float y = q.y;
    float res = 1e9;
    if (R.baseH > 0.01)
    {
        float body = sdBox2(float2(d - 0.009, y - (R.baseH - 0.014) * 0.5), float2(0.011, (R.baseH - 0.014) * 0.5));
        float cap = length(float2(d - 0.010, y - (R.baseH - 0.014))) - 0.013;
        float shoe = max(length(float2(d - 0.020, y)) - 0.014, -y);
        res = min(res, min(min(body, cap), shoe));
    }
    if (R.railH > 0.01)
    {
        float rail = max(length(float2(d, y - R.railH)) - 0.018, -d - 0.001);
        res = min(res, rail);
    }
    if (R.crown > 0.01)
    {
        float Rc = R.crown;
        float corner = sdBox2(float2(d - Rc * 0.5, y - (R.H - Rc * 0.5)), float2(Rc * 0.5, Rc * 0.5));
        float cove = Rc - length(float2(d - Rc, y - (R.H - Rc)));
        float crownS = max(corner, cove);
        float bead = length(float2(d - 0.012, y - (R.H - Rc - 0.006))) - 0.014;
        float fillet = length(float2(d - Rc - 0.010, y - (R.H - 0.004))) - 0.012;
        res = min(res, min(crownS, min(bead, fillet)));
    }
    return res;
}

float wallTrimsCut(float3 q, int w, BRRoom R, float trims)
{
    if (trims > 0.2) return trims;
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = scOpen(i);
        if (!o.active || o.wall != w) continue;
        float3 lq = openLocal(q, o, R);
        float hw = o.width * 0.5;
        float cut;
        if (o.kind == OPEN_FIREPLACE)
            cut = sdAabb(lq, float3(-hw, -1.0, -1.0), float3(hw, R.H - R.crown - 0.002, o.depth + 0.5));
        else
            cut = sdAabb(lq, float3(-hw - 0.077, -2.0, -0.5), float3(hw + 0.077, o.height + 0.075 + 0.02, 0.5));
        trims = max(trims, -cut);
    }
    return trims;
}

// --------------------------------------------------------------------------------------------
// SHELL, split in two:
//   return value  -- the closest DETAIL: everything that is not one of the room's slab faces
//                    (frames, trims, radiators, door, chimney breast, surround, hearth ...)
//   slab          -- the wall/floor/ceiling slabs with every opening and the firebox cut,
//                    material chosen from where the point sits (floor/ceiling/wall/reveal).
// Primary and shadow rays step on the detail distance and intersect the box faces analytically,
// so a floor seen from eye height never makes a grazing march crawl. `detail` false is the
// coarse field the GI probes use.
SHit shellMapSplit(float3 q, bool detail, out SHit slab)
{
    BRRoom R = scRoom();
    float3 lo = float3(R.x0, 0.0, R.z0), hi = float3(R.x1, R.H, R.z1);
    float dIn = sdAabb(q, lo, hi);
    float3 tt = float3(R.T, R.T, R.T);
    float dOut = sdAabb(q, lo - tt, hi + tt);
    float solid = max(dOut, -dIn);
    float cavity = 1e9;
    float breastD = 1e9;
    SHit h = shit(1e9, MAT_WALL, PART_SHELL, -1);
    float dummy = 1e9;

    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = scOpen(i);
        if (!o.active) continue;
        float3 lq = openLocal(q, o, R);
        float hw = o.width * 0.5;
        float reach = (o.kind == OPEN_FIREPLACE) ? o.depth + 0.6 : 0.6;
        float bound = sdAabb(lq, float3(-hw - 0.5, -o.sill - 0.1, -R.T - 0.2), float3(hw + 0.5, max(o.height + 0.35, R.H - o.sill + 0.1), reach));
        // a cut raises distance: never prune it while inside or near the solid
        if (bound > max(solid, 0.0) + 0.02 && bound > h.d) continue;
        if (o.kind == OPEN_FIREPLACE)
        {
            fireplace(lq, o, R, dummy, cavity, breastD, h, i);
        }
        else
        {
            solid = max(solid, -openingHole(lq, o, R.T));
            if (detail)
            {
                if (brOpenIsGlazed(o.kind)) windowFrame(lq, o, R.T, h, i);
                if (o.kind == OPEN_DOOR) doorLeaf(lq, o, h, i);
                openingTrim(lq, o, R.T, h, i);
                if (o.radiator && (R.flags & ROOM_FLAG_RADIATORS) != 0) radiator(lq, o, h, i);
                if (o.curtains && (R.flags & ROOM_FLAG_CURTAINS) != 0) curtainRod(lq, o, h, i);
            }
            else if (o.kind == OPEN_DOOR)
            {
                float leaf = sdAabb(lq, float3(-hw, 0.0, -0.05), float3(hw, o.height, -0.01));
                hmin(h, leaf, MAT_DOOR, PART_DOOR, -1 - i);
            }
        }
    }
    solid = max(solid, -cavity);

    if (detail)
    {
        // trims along the two nearest walls (corners need both), clipped to the interior
        int wx = (q.x - R.x0 < R.x1 - q.x) ? WALL_W : WALL_E;
        int wz = (q.z - R.z0 < R.z1 - q.z) ? WALL_S : WALL_N;
        float tx = wallTrims(q, wx, R);
        float tz = wallTrims(q, wz, R);
        if (tx < h.d + 0.2) tx = wallTrimsCut(q, wx, R, tx);
        if (tz < h.d + 0.2) tz = wallTrimsCut(q, wz, R, tz);
        float trims = max(min(tx, tz), dIn - 0.0005);
        hmin(h, trims, MAT_TRIM, PART_TRIM, -1);
    }

    int mat = MAT_WALL, part = PART_SHELL;
    if (q.y < 0.004 && dIn < 0.01) { mat = MAT_FLOOR; part = PART_FLOOR; }
    else if (q.y > R.H - 0.004 && dIn < 0.01) { mat = MAT_CEILING; part = PART_CEILING; }
    else if (dIn > 0.002) part = PART_REVEAL;
    if (cavity < 0.012) { mat = MAT_BLACKMETAL; part = PART_FIREBOX; }
    slab = shit(solid, mat, part, -1);
    return h;
}

SHit shellMap(float3 q, bool detail)
{
    SHit slab;
    SHit h = shellMapSplit(q, detail, slab);
    if (slab.d < h.d) h = slab;
    return h;
}

// Is a point on the interior box surface inside an opening (or the firebox mouth), i.e. may a
// ray continue past the analytic box face here?
bool boxFacePassable(float3 x)
{
    BRRoom R = scRoom();
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = scOpen(i);
        if (!o.active) continue;
        float3 lq = openLocal(x, o, R);
        if (abs(lq.z) > 0.02) continue;
        float hw = o.width * 0.5;
        if (o.kind == OPEN_FIREPLACE)
        {
            if (abs(lq.x) < o.cols * 0.5 && lq.y < o.rows) return true;
            continue;
        }
        if (o.kind == OPEN_ARCH)
        {
            float cy = o.height - hw;
            if (abs(lq.x) < hw && lq.y > 0.0 && (lq.y < cy || length(float2(lq.x, lq.y - cy)) < hw)) return true;
            continue;
        }
        if (abs(lq.x) < hw && lq.y > 0.0 && lq.y < o.height) return true;
    }
    return false;
}

// Exit distance of a ray from the interior box (camera inside), and the face normal it exits through.
float boxExit(float3 ro, float3 rd, out float3 faceN)
{
    BRRoom R = scRoom();
    float3 lo = float3(R.x0, 0.0, R.z0), hi = float3(R.x1, R.H, R.z1);
    float3 inv = 1.0 / (abs(rd) > 1e-6 ? rd : float3(1e-6, 1e-6, 1e-6));
    float3 t0 = (lo - ro) * inv, t1 = (hi - ro) * inv;
    float3 tf = max(t0, t1);
    float te = min(tf.x, min(tf.y, tf.z));
    faceN = (te == tf.x) ? float3(-sign(rd.x), 0, 0) : ((te == tf.y) ? float3(0, -sign(rd.y), 0) : float3(0, 0, -sign(rd.z)));
    return te;
}

bool insideRoomBox(float3 x, float pad)
{
    BRRoom R = scRoom();
    return x.x > R.x0 + pad && x.x < R.x1 - pad && x.y > pad && x.y < R.H - pad && x.z > R.z0 + pad && x.z < R.z1 - pad;
}
bool outsideBuilding(float3 x)
{
    BRRoom R = scRoom();
    float T = R.T + 0.05;
    return x.x < R.x0 - T || x.x > R.x1 + T || x.y < -T || x.y > R.H + T || x.z < R.z0 - T || x.z > R.z1 + T;
}

// --------------------------------------------------------------------------------------------
// VEIL: glass panes and sheer curtains (thin, translucent).
float sheerPanel(float3 lq, float x0, float x1, float y0, float y1, float zc, float folds, float seed)
{
    float t = (lq.x - x0) / max(x1 - x0, 1e-3);
    float amp = 0.028;
    float k = 2.0 * 3.14159265 / max((x1 - x0) / folds, 0.02);
    float sway = 0.006 * sin(lq.y * 3.1 + seed * 7.0);
    float surf = zc + amp * sin(lq.x * k + seed * 3.0) + sway;
    float slope = amp * k;
    float dz = abs(lq.z - surf) / sqrt(1.0 + slope * slope * 0.5) - 0.0015;
    float box = sdAabb(lq, float3(x0, y0, zc - 0.08), float3(x1, y1, zc + 0.08));
    return max(dz, box);
}

SHit veilMap(float3 q)
{
    BRRoom R = scRoom();
    SHit h = shit(1e9, MAT_GLASS, PART_GLASS, -1);
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = scOpen(i);
        if (!o.active || !brOpenIsGlazed(o.kind)) continue;
        float3 lq = openLocal(q, o, R);
        float hw = o.width * 0.5;
        float bound = sdAabb(lq, float3(-hw - 0.5, -o.sill, -R.T - 0.1), float3(hw + 0.5, o.height + 0.3, 0.25));
        if (bound > h.d) continue;
        float dc = -R.T + 0.075;
        float glass;
        if (o.kind == OPEN_DOUBLEHUNG)
        {
            float mid = o.height * 0.5;
            glass = min(sdAabb(lq, float3(-hw + 0.06, 0.06, dc + 0.022), float3(hw - 0.06, mid, dc + 0.026)),
                        sdAabb(lq, float3(-hw + 0.06, mid, dc - 0.026), float3(hw - 0.06, o.height - 0.06, dc - 0.022)));
        }
        else
        {
            float yb = (o.kind == OPEN_FRENCH) ? 0.36 : 0.06;
            glass = sdAabb(lq, float3(-hw + 0.06, yb, dc - 0.002), float3(hw - 0.06, o.height - 0.06, dc + 0.002));
        }
        hmin(h, glass, MAT_GLASS, PART_GLASS, -1 - i);
        if (o.curtains && (R.flags & ROOM_FLAG_CURTAINS) != 0)
        {
            float ext = hw + 0.36;
            float y1 = o.height + 0.165;
            float y0 = -o.sill + 0.012;
            float left = sheerPanel(lq, -ext, -hw + 0.22, y0, y1, 0.085, 7.0, (float)i);
            float right = sheerPanel(lq, hw - 0.22, ext, y0, y1, 0.085, 7.0, (float)i + 0.5);
            hmin(h, min(left, right), MAT_SHEER, PART_SHEER, -1 - i);
        }
    }
    return h;
}

#endif
