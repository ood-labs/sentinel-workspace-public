// br_furniture.hlsli -- SDF models for the BR_Furnish catalogue (br_furn_defs.hlsli).
//
// Every model is written in the piece's LOCAL frame (origin at the footprint centre on its base,
// +z front, +y up) and is told its size, so a stretched sofa stays a sofa: cushions re-divide,
// arms keep their width, legs stay legs. Parts carry their own material slot and a part id; the
// part id seeds pattern variation (book spines, leaf tones) and lets the shader treat a print
// differently from its frame.
//
// Construction rules followed throughout (they are what make an SDF read as furniture):
//   * nothing is sharp: every box has a radius at the scale of the real object's edge
//   * upholstery is CROWNED: cushions bulge a centimetre or two at their centres
//   * parts meet with a visible seam: cushions are separate bodies with a 4-6 mm gap
//   * legs taper, and stand in from the corners
#ifndef BR_FURNITURE_HLSLI
#define BR_FURNITURE_HLSLI

#include "../_shared/br_sdf.hlsli"
#include "../_shared/br_furn_defs.hlsli"

#define FP_BODY     0
#define FP_SEAT     1
#define FP_BACK     2
#define FP_LEG      3
#define FP_ARM      4
#define FP_TOP      5
#define FP_SHADE    6
#define FP_BULB     7
#define FP_METAL    8
#define FP_IMAGE    9
#define FP_MIRROR   10
#define FP_SOIL     11
#define FP_POT      12
#define FP_FRINGE   13
#define FP_MAT      14          // a framed print's mat (passe-partout)
#define FP_BOOK     16          // books occupy 16..63 (part id carries the book's identity)

// part id stored in SHit.part = PART_FURN + local part (book parts up to PART_FURN + 63)
#define FPART(x) (32 + (x))

// a cushion: rounded box crowned toward its centre
float sdCushion(float3 p, float3 halfSize, float r, float crown)
{
    float d = sdRBox(p, halfSize, r);
    float2 n = saturate(1.0 - (p.xz * p.xz) / max(halfSize.xz * halfSize.xz, 1e-4));
    float bulge = n.x * n.y;
    return d - crown * bulge;
}

float3 rotX(float3 p, float a) { float c = cos(a), s = sin(a); return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z); }
float3 rotY(float3 p, float a) { float c = cos(a), s = sin(a); return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z); }
float3 rotZ(float3 p, float a) { float c = cos(a), s = sin(a); return float3(c * p.x - s * p.y, s * p.x + c * p.y, p.z); }

// ---------------------------------------------------------------------------------------------
// UPHOLSTERED SEATING: sofa (track / rolled / loveseat) and chairs (lounge / club / wingback)
void seatModel(float3 q, int kind, int v, float3 S, int matA, int matB, int obj, inout SHit h)
{
    float w = S.x, ht = S.y, d = S.z;
    bool chair = kind == FK_CHAIR;
    float legH = chair ? ((v == 0) ? 0.17 : 0.10) : ((v == 1) ? 0.07 : 0.13);
    float seatTop = chair ? ((v == 0) ? 0.41 : 0.43) : 0.45;
    float armW = chair ? ((v == 0) ? 0.11 : 0.16) : ((v == 1) ? 0.19 : 0.16);
    float armTop = chair ? ((v == 2) ? 0.64 : (v == 0) ? 0.56 : 0.66) : ((v == 1) ? 0.66 : 0.62);
    float backD = (v == 1 && chair) ? 0.24 : 0.19;
    float deckTop = legH + 0.19;
    // base / frame
    float base = sdRAabb(q, float3(-w * 0.5, legH, -d * 0.5), float3(w * 0.5, deckTop, d * 0.5 - 0.01), 0.03);
    // back frame
    float backTop = ht - ((chair && v == 2) ? 0.02 : 0.10);
    float back = sdRAabb(q, float3(-w * 0.5 + 0.01, legH, -d * 0.5), float3(w * 0.5 - 0.01, backTop, -d * 0.5 + backD), 0.06);
    // arms
    float arms;
    float ax = abs(q.x) - (w * 0.5 - armW * 0.5);
    float3 aq = float3(ax, q.y, q.z);
    if (!chair && v == 1)
    {
        // rolled arm: a box topped by an outward roll running front to back
        float box = sdRAabb(aq, float3(-armW * 0.5, legH, -d * 0.5), float3(armW * 0.5, armTop - 0.08, d * 0.5), 0.03);
        float roll = max(length(float2(aq.x - 0.025, aq.y - (armTop - 0.07))) - armW * 0.62, abs(aq.z) - d * 0.5);
        arms = sminK(box, roll, 0.03);
    }
    else
    {
        arms = sdRAabb(aq, float3(-armW * 0.5, legH, -d * 0.5), float3(armW * 0.5, armTop, d * 0.5), (v == 0 && chair) ? 0.035 : 0.055);
    }
    if (chair && v == 2)
    {
        // wingback: wings rise from the arms along the front of the back
        float wing = sdRAabb(aq, float3(-armW * 0.5, armTop - 0.05, -d * 0.5), float3(armW * 0.5 + 0.02, ht - 0.12, -d * 0.5 + 0.34), 0.06);
        arms = min(arms, wing);
    }
    float body = min(min(base, back), arms);
    hmin(h, body, matA, FPART(FP_BODY), obj);

    // seat cushions
    float innerW = w - 2.0 * armW - 0.01;
    int n = chair ? 1 : (int)clamp(round(innerW / 0.64), 1.0, 3.0);
    float cw = innerW / (float)n;
    float k = clamp(floor((q.x + innerW * 0.5) / cw), 0.0, (float)(n - 1));
    float cx = -innerW * 0.5 + (k + 0.5) * cw;
    float3 sc = float3(cx, (deckTop + seatTop) * 0.5, (-d * 0.5 + backD + d * 0.5 - 0.005) * 0.5);
    float3 shalf = float3(cw * 0.5 - 0.003, (seatTop - deckTop) * 0.5, (d - backD - 0.005) * 0.5);
    float seat = sdCushion((q - sc).xzy * float3(1, 1, 1), shalf.xzy, 0.055, 0.016);
    seat = sdCushion(float3(q.x - sc.x, q.y - sc.y, q.z - sc.z), shalf, 0.055, 0.016);
    hmin(h, seat, matA, FPART(FP_SEAT), obj);

    // back cushions, leaning back ~12 degrees
    float bTop = backTop + ((chair && v == 2) ? -0.02 : 0.05);
    float bBot = seatTop - 0.03;
    float3 bc = float3(cx, (bTop + bBot) * 0.5, -d * 0.5 + backD + 0.09);
    float3 bq = rotX(q - bc, -0.21);
    float3 bhalf = float3(cw * 0.5 - 0.004, (bTop - bBot) * 0.5, 0.085);
    float backC = sdRBox(bq, bhalf, 0.075) - 0.02 * saturate(1.0 - bq.x * bq.x / max(bhalf.x * bhalf.x, 1e-4)) * saturate(1.0 - bq.y * bq.y / max(bhalf.y * bhalf.y, 1e-4));
    if (!(chair && v == 1)) hmin(h, backC, matA, FPART(FP_BACK), obj);

    // legs: tapered, set in from the corners (bun feet for the rolled-arm sofa)
    float lx = w * 0.5 - 0.08, lz = d * 0.5 - 0.08;
    float3 lp = float3(abs(q.x) - lx, q.y, abs(q.z) - lz);
    float leg;
    if (!chair && v == 1) leg = length(lp - float3(0, legH * 0.5, 0)) - legH * 0.55;
    else
    {
        float splay = (chair && v == 0) ? 0.03 : 0.012;
        leg = sdRoundCone(lp, float3(splay, 0.0, splay), float3(0, legH + 0.005, 0), 0.011, 0.019);
    }
    hmin(h, leg, matB, FPART(FP_LEG), obj);
}

// ---------------------------------------------------------------------------------------------
void tableModel(float3 q, int kind, int v, float3 S, int matA, int matB, int obj, inout SHit h)
{
    float w = S.x, ht = S.y, d = S.z;
    if (kind == FK_COFFEE && v == 1)
    {
        // round travertine plinth table
        float top = sdRCylY(q - float3(0, ht - 0.03, 0), 0.03, w * 0.5, 0.012);
        float drum = sdRCylY(q - float3(0, (ht - 0.06) * 0.5, 0), (ht - 0.06) * 0.5, w * 0.27, 0.01);
        hmin(h, min(top, drum), matA, FPART(FP_TOP), obj);
        float ring = sdTorusY(q - float3(0, 0.012, 0), w * 0.27, 0.008);
        hmin(h, ring, matB, FPART(FP_METAL), obj);
        return;
    }
    if (kind == FK_COFFEE && v == 2)
    {
        // upholstered ottoman
        float otto = sdCushion(q - float3(0, ht * 0.5 + 0.03, 0), float3(w * 0.5, ht * 0.5 - 0.03, d * 0.5), 0.07, 0.02);
        hmin(h, otto, matA, FPART(FP_BODY), obj);
        float3 lp = float3(abs(q.x) - (w * 0.5 - 0.07), q.y, abs(q.z) - (d * 0.5 - 0.07));
        hmin(h, sdRoundCone(lp, float3(0, 0, 0), float3(0, 0.07, 0), 0.012, 0.016), matB, FPART(FP_LEG), obj);
        return;
    }
    if (kind == FK_SIDE && v == 0)
    {
        float top = sdRCylY(q - float3(0, ht - 0.015, 0), 0.015, w * 0.5, 0.006);
        float col = sdCylY(q - float3(0, ht * 0.5, 0), ht * 0.5, 0.032);
        float foot = sdRCylY(q - float3(0, 0.014, 0), 0.014, w * 0.36, 0.006);
        hmin(h, min(min(top, col), foot), matA, FPART(FP_TOP), obj);
        hmin(h, sdTorusY(q - float3(0, 0.03, 0), w * 0.36 - 0.01, 0.005), matB, FPART(FP_METAL), obj);
        return;
    }
    if (kind == FK_SIDE && v == 2)
    {
        // ceramic drum, a little barrel and a soft lip
        float r = w * 0.5 * (0.94 + 0.06 * sin(saturate(q.y / ht) * 3.14159));
        float drum = max(length(q.xz) - r, abs(q.y - ht * 0.5) - ht * 0.5) ;
        drum = sdRCylY(q - float3(0, ht * 0.5, 0), ht * 0.5, w * 0.5, 0.02) + (w * 0.5 - r);
        hmin(h, drum, matA, FPART(FP_TOP), obj);
        return;
    }
    // rectangular wood table (coffee v0, side v1): top, apron, tapered legs
    float top = sdRAabb(q, float3(-w * 0.5, ht - 0.032, -d * 0.5), float3(w * 0.5, ht, d * 0.5), 0.007);
    float apron = sdRAabb(q, float3(-w * 0.5 + 0.06, ht - 0.085, -d * 0.5 + 0.06), float3(w * 0.5 - 0.06, ht - 0.03, d * 0.5 - 0.06), 0.004);
    float hollow = sdAabb(q, float3(-w * 0.5 + 0.08, ht - 0.09, -d * 0.5 + 0.08), float3(w * 0.5 - 0.08, ht - 0.035, d * 0.5 - 0.08));
    apron = max(apron, -hollow);
    float3 lp = float3(abs(q.x) - (w * 0.5 - 0.085), q.y, abs(q.z) - (d * 0.5 - 0.085));
    float leg = sdRoundCone(lp, float3(0.025, 0.0, 0.025), float3(0.0, ht - 0.03, 0.0), 0.011, 0.02);
    float shelf = (kind == FK_SIDE) ? sdRAabb(q, float3(-w * 0.5 + 0.07, 0.14, -d * 0.5 + 0.07), float3(w * 0.5 - 0.07, 0.16, d * 0.5 - 0.07), 0.004) : 1e9;
    hmin(h, min(min(top, apron), shelf), matA, FPART(FP_TOP), obj);
    hmin(h, leg, matA, FPART(FP_LEG), obj);
}

// ---------------------------------------------------------------------------------------------
void rugModel(float3 q, float3 S, int obj, inout SHit h)
{
    float body = sdRAabb(q, float3(-S.x * 0.5, 0.0, -S.z * 0.5), float3(S.x * 0.5, 0.011, S.z * 0.5), 0.004);
    hmin(h, body, MAT_RUG, FPART(FP_BODY), obj);
    // knotted fringe at both short ends
    float fz = abs(q.z) - S.z * 0.5;
    if (fz > -0.01 && fz < 0.08)
    {
        float pitch = 0.012;
        float fx = q.x - pitch * round(q.x / pitch);
        float strand = max(sdBox2(float2(fx, q.y - 0.0025), float2(0.0035, 0.0025)), abs(fz - 0.035) - 0.035);
        strand = max(strand, abs(q.x) - S.x * 0.5 + 0.01);
        hmin(h, strand, MAT_RUG, FPART(FP_FRINGE), obj);
    }
}

// ---------------------------------------------------------------------------------------------
// LAMPS. A fabric shade is a thin open shell (light leaves top and bottom, glows through the sides).
// EXACT: the distance, in the (radius, height) half-plane, to the shade's profile segment. The old
// horizontal measure |r - r(y)| over-read the distance to a tapered drum by 1/cos(taper), 4% on
// the table lamps: seen from above, a ray stepped clean through the 5 mm wall and an arch of the
// shade showed the stem and bulb inside it.
float shadeShell(float3 p, float rBot, float rTop, float y0, float y1)
{
    float2 aq = float2(length(p.xz) - rBot, p.y - y0);
    float2 ab = float2(rTop - rBot, y1 - y0);
    float h = saturate(dot(aq, ab) / max(dot(ab, ab), 1e-8));
    return length(aq - ab * h) - 0.0025;
}

void lampModel(float3 q, int kind, int v, float3 S, int matA, int matB, int obj, float roomH, float y0, inout SHit h)
{
    if (kind == FK_FLOORLAMP)
    {
        if (v == 0)
        {
            // arc lamp: marble foot, brass column, an arc over the seat, a domed shade
            float foot = sdRCylY(q - float3(0, 0.02, 0), 0.02, 0.17, 0.008);
            hmin(h, foot, MAT_MARBLE, FPART(FP_BODY), obj);
            float pole = sdCapsuleSeg(q, float3(0, 0.03, 0), float3(0, 1.30, 0), 0.012);
            float3 c = float3(0, 1.30, 0.62);
            float3 pc = q - c;
            // 0 at the column, pi/2 over the top, unwrapped past pi so the far side to 3.32 rad is
            // part of the arc (atan2 alone stops at pi and left an 11 cm gap before the tip)
            float ang = (abs(pc.y) + abs(pc.z) > 1e-7) ? atan2(pc.y, -pc.z) : 0.0;
            ang = (ang < -1.2) ? ang + 6.2831853 : ang;
            float arc = length(float2(length(pc.yz) - 0.62, pc.x)) - 0.011;
            float endA = sdCapsuleSeg(q, float3(0, 1.30, 0), float3(0, 1.30, 0), 0.011);
            // outside the swept angle the nearest point is an END, and both ends carry a sphere
            arc = (ang > 0.0 && ang < 3.32) ? arc : 1e9;
            float3 tip = c + float3(0, sin(3.32) * 0.62, -cos(3.32) * 0.62);
            arc = min(arc, length(q - tip) - 0.016);
            hmin(h, min(pole, min(arc, endA)), matA, FPART(FP_METAL), obj);
            // a hemispherical dome hung from the tip, open underneath, bulb inside
            float3 sp = q - (tip - float3(0, 0.20, 0));
            float dome = max(abs(length(sp) - 0.19) - 0.0022, -sp.y);
            hmin(h, dome, matA, FPART(FP_SHADE), obj);
            hmin(h, length(sp - float3(0, 0.05, 0)) - 0.035, MAT_BULB, FPART(FP_BULB), obj);
            return;
        }
        if (v == 1)
        {
            float legs = 1e9;
            [unroll] for (int i = 0; i < 3; i++)
            {
                float a = (float)i * 2.0944 + 0.3;
                float3 f = float3(sin(a) * 0.27, 0.0, cos(a) * 0.27);
                legs = min(legs, sdCapsuleSeg(q, f, float3(0, 1.24, 0), 0.012));
            }
            hmin(h, legs, matA, FPART(FP_LEG), obj);
            hmin(h, shadeShell(q, 0.25, 0.22, 1.24, 1.56), matB, FPART(FP_SHADE), obj);
            hmin(h, length(q - float3(0, 1.36, 0)) - 0.03, MAT_BULB, FPART(FP_BULB), obj);
            return;
        }
        float base = sdRCylY(q - float3(0, 0.012, 0), 0.012, 0.14, 0.006);
        float pole = sdCapsuleSeg(q, float3(0, 0.02, 0), float3(0, 1.34, 0), 0.011);
        hmin(h, min(base, pole), matA, FPART(FP_METAL), obj);
        hmin(h, shadeShell(q, 0.21, 0.18, 1.30, 1.62), matB, FPART(FP_SHADE), obj);
        hmin(h, length(q - float3(0, 1.42, 0)) - 0.03, MAT_BULB, FPART(FP_BULB), obj);
        return;
    }
    if (kind == FK_TABLELAMP)
    {
        if (v == 0)
        {
            float a = sdEllipsoid(q - float3(0, 0.13, 0), float3(0.13, 0.125, 0.13));
            float b = sdEllipsoid(q - float3(0, 0.29, 0), float3(0.075, 0.08, 0.075));
            float base = sminK(a, b, 0.04);
            hmin(h, base, matA, FPART(FP_BODY), obj);
            float neck = sdCapsuleSeg(q, float3(0, 0.34, 0), float3(0, 0.44, 0), 0.008);
            hmin(h, neck, MAT_BRASS, FPART(FP_METAL), obj);
        }
        else
        {
            float foot = sdRCylY(q - float3(0, 0.012, 0), 0.012, 0.075, 0.005);
            float stem = sdCylY(q - float3(0, 0.2, 0), 0.19, 0.016);
            float rings = sdTorusY(float3(q.x, q.y - 0.07 * round(q.y / 0.07), q.z), 0.019, 0.006);
            rings = max(rings, abs(q.y - 0.2) - 0.18);
            hmin(h, min(min(foot, stem), rings), matA, FPART(FP_METAL), obj);
        }
        hmin(h, shadeShell(q, (v == 0) ? 0.19 : 0.16, (v == 0) ? 0.155 : 0.095, 0.34, (v == 0) ? 0.60 : 0.56), matB, FPART(FP_SHADE), obj);
        hmin(h, length(q - float3(0, 0.45, 0)) - 0.028, MAT_BULB, FPART(FP_BULB), obj);
        return;
    }
    // pendant: hung from the ceiling on a cord; y0 is the bottom of the fitting
    float topY = roomH - y0;                 // local height of the ceiling
    if (v == 0)
    {
        float globe = abs(length(q - float3(0, 0.20, 0)) - 0.20) - 0.003;
        hmin(h, globe, MAT_SHADE, FPART(FP_SHADE), obj);
        hmin(h, length(q - float3(0, 0.20, 0)) - 0.035, MAT_BULB, FPART(FP_BULB), obj);
    }
    else if (v == 1)
    {
        // a paper shell 4 mm thick needs a distance that never over-reads: the scaled-sphere bound
        float lantern = abs((length((q - float3(0, 0.27, 0)) / float3(0.25, 0.27, 0.25)) - 1.0) * 0.25) - 0.002;
        lantern = max(lantern, -(abs(q.y - 0.27) - 0.25));
        hmin(h, lantern, MAT_SHADE, FPART(FP_SHADE), obj);
        hmin(h, length(q - float3(0, 0.27, 0)) - 0.035, MAT_BULB, FPART(FP_BULB), obj);
    }
    else
    {
        float3 sp = q - float3(0, 0.0, 0);
        float dome = max(abs(length(sp) - 0.23) - 0.002, -sp.y);
        hmin(h, dome, matA, FPART(FP_SHADE), obj);
        hmin(h, length(q - float3(0, 0.06, 0)) - 0.035, MAT_BULB, FPART(FP_BULB), obj);
    }
    float capY = (v == 1) ? 0.55 : (v == 2) ? 0.24 : 0.41;
    float cap = sdCylY(q - float3(0, capY + 0.02, 0), 0.025, 0.035);
    float cord = sdCapsuleSeg(q, float3(0, capY + 0.04, 0), float3(0, topY, 0), 0.0035);
    float rose = sdRCylY(q - float3(0, topY - 0.012, 0), 0.012, 0.06, 0.004);
    hmin(h, min(min(cap, cord), rose), MAT_BRASS, FPART(FP_METAL), obj);
}

// ---------------------------------------------------------------------------------------------
// BOOKSHELF with a library: each 38 mm slot holds a book of its own height and depth, or a gap.
// A book beside a gap may lean into it, far enough to rest its top on the book beyond.
float2 shelfHash(float k, float row, float seed)
{
    return float2(brHash01((uint)(k * 31.0 + row * 977.0 + seed * 7919.0) + 13u),
                  brHash01((uint)(k * 17.0 + row * 263.0 + seed * 1931.0) + 71u));
}
bool shelfGap(float2 hh, float k, float kMax) { return k < 0.0 || k > kMax || hh.x < 0.09 || (hh.y > 0.93 && k > 2.0); }

// The book in slot k (distance, with the board it stands on cut away). `leanInto` says the next
// slot along +x is empty: the book then pivots about its foot until its top meets the next book.
float shelfBook(float3 q, float k, float2 hh, bool leanInto, float rowY, float pitch, float d, float inner, float bw)
{
    float bh = lerp(0.20, min(pitch - 0.05, 0.31), hh.y);
    float bt = lerp(0.022, 0.036, frac(hh.x * 7.0));
    float bd = lerp(0.15, d - 0.05, frac(hh.x * 13.0));
    // the top travels across the empty slot and stops 2 mm short of the thickest possible neighbour
    float sl = (leanInto && frac(hh.x * 29.0) > 0.40) ? min((2.0 * bw - bt * 0.5 - 0.020) / bh, 0.30) : 0.0;
    float cl = sqrt(1.0 - sl * sl);
    float bx = -inner + (k + 0.5) * bw;
    float3 bp = q - float3(bx, rowY, -d * 0.5 + 0.012 + bd * 0.5);
    bp = float3(cl * bp.x - sl * bp.y, sl * bp.x + cl * bp.y, bp.z) - float3(0, bh * 0.5, 0);
    float book = sdRBox(bp, float3(bt * 0.5, bh * 0.5, bd * 0.5), 0.0035);
    return max(book, -(q.y - rowY));      // never through the shelf
}

void shelfModel(float3 q, int v, float3 S, int matA, int obj, float seed, inout SHit h)
{
    float w = S.x, ht = S.y, d = S.z;
    float t = 0.024;
    float sides = sdRAabb(float3(abs(q.x), q.y, q.z), float3(w * 0.5 - t, 0.0, -d * 0.5), float3(w * 0.5, ht, d * 0.5), 0.003);
    float top = sdRAabb(q, float3(-w * 0.5, ht - t, -d * 0.5), float3(w * 0.5, ht, d * 0.5), 0.003);
    float plinth = sdRAabb(q, float3(-w * 0.5 + t, 0.0, -d * 0.5 + 0.02), float3(w * 0.5 - t, 0.085, d * 0.5 - 0.015), 0.003);
    float backP = sdAabb(q, float3(-w * 0.5 + t, 0.085, -d * 0.5), float3(w * 0.5 - t, ht - t, -d * 0.5 + 0.008));
    int shelves = (v == 0) ? 5 : 4;
    float pitch = (ht - 0.085 - t) / (float)shelves;
    float sy = 0.085 + pitch * clamp(round((q.y - 0.085) / pitch), 1.0, (float)(shelves - 1));
    float board = sdRAabb(q, float3(-w * 0.5 + t, sy - 0.022, -d * 0.5 + 0.008), float3(w * 0.5 - t, sy, d * 0.5 - 0.005), 0.003);
    hmin(h, min(min(sides, top), min(plinth, board)), matA, FPART(FP_BODY), obj);
    // the back board is its own part: a matte panel (shade.hlsl), not the case's varnish, which
    // mirrored the room behind the camera between the rows
    hmin(h, backP, matA, FPART(FP_BACK), obj);
    // books: slot index along x, row index along y. A distance taken from this slot's book alone
    // is not a bound: beside a short book or a gap the ray stepped clean into a taller or leaning
    // neighbour, and every spine came out sawn into steps. So the field is the nearest of the
    // slots that can reach this one -- two to the left (a lean crosses one empty slot), one to the
    // right -- and anything further is at least 39 mm away, which caps the step.
    float row = clamp(floor((q.y - 0.085) / pitch), 0.0, (float)(shelves - 1));
    float rowY = 0.085 + row * pitch;
    float bw = 0.038;
    float inner = w * 0.5 - t - 0.01;
    float kMax = floor(2.0 * inner / bw) - 1.0;
    float k = clamp(floor((q.x + inner) / bw), 0.0, kMax);
    // every book of the row lies inside this slab, so outside it the slab IS the bound: the slot
    // search below runs only where a book can actually be near
    float slab = sdAabb(q, float3(-inner, rowY, -d * 0.5 + 0.012), float3(inner, rowY + pitch - 0.05, d * 0.5 - 0.038));
    float best = slab;
    float bestH = 0.0;
    [branch] if (slab < 0.01)
    {
        best = max(0.058 - abs(q.x - (-inner + (k + 0.5) * bw)), slab);
        // right to left, so each slot already knows whether the slot to its right is empty
        float ks = k + 2.0;
        bool nextGap = shelfGap(shelfHash(ks, row, seed), ks, kMax);
        [unroll] for (int s = 0; s < 4; s++)
        {
            ks -= 1.0;
            float2 hh = shelfHash(ks, row, seed);
            bool gap = shelfGap(hh, ks, kMax);
            // the last book of a row has the side panel beside it, not a gap to lean into
            float b = gap ? 1e9 : shelfBook(q, ks, hh, nextGap && ks + 1.0 <= kMax, rowY, pitch, d, inner, bw);
            if (b < best) { best = b; bestH = hh.x; }
            nextGap = gap;
        }
    }
    hmin(h, best, MAT_PAPER, FPART(FP_BOOK + ((int)(bestH * 47.0) & 47)), obj);
}

void consoleModel(float3 q, float3 S, int matA, int matB, int obj, inout SHit h)
{
    float w = S.x, ht = S.y, d = S.z;
    float legH = 0.13;
    float carcass = sdRAabb(q, float3(-w * 0.5, legH, -d * 0.5), float3(w * 0.5, ht, d * 0.5), 0.01);
    // door gaps on the front face
    float pitch = w / 3.0;
    float gx = q.x - pitch * round(q.x / pitch);
    float groove = max(max(abs(gx) - 0.0015, abs(q.z - d * 0.5) - 0.01), abs(q.y - (legH + ht) * 0.5) - (ht - legH) * 0.5 + 0.03);
    groove = max(groove, abs(q.x) - (w * 0.5 - 0.05));
    carcass = max(carcass, -groove);
    hmin(h, carcass, matA, FPART(FP_BODY), obj);
    float3 lp = float3(abs(q.x) - (w * 0.5 - 0.07), q.y, abs(q.z) - (d * 0.5 - 0.06));
    hmin(h, sdRoundCone(lp, float3(0.01, 0.0, 0.01), float3(0, legH + 0.005, 0), 0.01, 0.017), matA, FPART(FP_LEG), obj);
    float3 pq = float3(q.x - pitch * round(q.x / pitch) - pitch * 0.32, q.y - (ht - 0.11), q.z - d * 0.5 - 0.012);
    float pull = sdCapsuleSeg(float3(abs(pq.x), pq.y, pq.z), float3(0, -0.04, 0), float3(0, 0.04, 0), 0.006);
    pull = max(pull, abs(q.x) - w * 0.5 + 0.08);
    hmin(h, pull, matB, FPART(FP_METAL), obj);
}

// ---------------------------------------------------------------------------------------------
// PLANTS: fiddle-leaf fig, snake plant, olive standard (br_plants.hlsli)
#include "../_shared/br_plants.hlsli"

// ---------------------------------------------------------------------------------------------
// WALL ART (local +z out of the wall, origin at the bottom centre on the wall face)

// The print's window in the mat (v0): half-width a, from yb up to yt in the piece's local frame.
// The margins are a fraction of the width, deeper at the bottom, as a framer cuts them.
void artWindow(float3 S, out float a, out float yb, out float yt)
{
    float fw = 0.030, m = 0.13 * S.x;
    a = max(S.x * 0.5 - fw - m, 0.03);
    yb = fw + m * 1.25;
    yt = max(S.y - fw - m, yb + 0.05);
}

void artModel(float3 q, int v, float3 S, int matA, int matB, int obj, inout SHit h)
{
    float w = S.x, ht = S.y, dz = S.z;
    float3 c = float3(0, ht * 0.5, dz * 0.5);
    if (v == 2)
    {
        float3 p = q - float3(0, ht * 0.5, 0.0);
        float rr = w * 0.5;
        float frame = length(float2(length(p.xy) - rr + 0.02, p.z - 0.02)) - 0.02;
        hmin(h, frame, matA, FPART(FP_METAL), obj);
        float glass = max(length(p.xy) - (rr - 0.02), abs(p.z - 0.012) - 0.004);
        hmin(h, glass, MAT_BLACKMETAL, FPART(FP_MIRROR), obj);
        return;
    }
    if (v == 1)
    {
        // gallery-wrapped canvas
        float canvas = sdRBox(q - c, float3(w * 0.5, ht * 0.5, dz * 0.5), 0.004);
        hmin(h, canvas, MAT_PAPER, FPART(FP_IMAGE), obj);
        return;
    }
    // v0: a framed print. The moulding steps down from a raised outer rim to an inner flat; a
    // cream mat sits just behind the flat with a bevel-cut window, and the print lies flush with
    // the back of the mat, 3 mm down. The bevel's white core is the bright hairline round the
    // image. (The old frame was a 3 cm black box around a print sunk 2 cm into it: its inner
    // walls read as a second frame inside the first.)
    float rim = 0.012, fw = 0.030;
    float outer = sdRBox(q - c, float3(w * 0.5, ht * 0.5, dz * 0.5), 0.003);
    float ringA = max(outer, -sdAabb(q, float3(-w * 0.5 + rim, rim, -1.0), float3(w * 0.5 - rim, ht - rim, 1.0)));
    float flatB = sdRAabb(q, float3(-w * 0.5 + rim - 0.002, rim - 0.002, 0.0), float3(w * 0.5 - rim + 0.002, ht - rim + 0.002, dz - 0.007), 0.0015);
    flatB = max(flatB, -sdAabb(q, float3(-w * 0.5 + fw, fw, -1.0), float3(w * 0.5 - fw, ht - fw, 1.0)));
    hmin(h, min(ringA, flatB), matA, FPART(FP_BODY), obj);
    float zf = dz - 0.009, zb = zf - 0.003;
    float a, yb, yt;
    artWindow(S, a, yb, yt);
    float sz = q.z - zb;
    float hole = max(max(abs(q.x) - a - sz, yb - sz - q.y), q.y - yt - sz) * 0.7071;
    float mat = max(sdAabb(q, float3(-w * 0.5 + rim, rim, zb), float3(w * 0.5 - rim, ht - rim, zf)), -hole);
    hmin(h, mat, MAT_PAPER, FPART(FP_MAT), obj);
    hmin(h, sdAabb(q, float3(-w * 0.5 + rim, rim, 0.0), float3(w * 0.5 - rim, ht - rim, zb)), MAT_PAPER, FPART(FP_IMAGE), obj);
}

// ---------------------------------------------------------------------------------------------
void smallModel(float3 q, int kind, int v, float3 S, int matA, int matB, int obj, float seed, inout SHit h)
{
    if (kind == FK_CUSHION)
    {
        float3 p = rotX(q - float3(0, S.y * 0.5, 0), -0.28);
        float3 hs = float3(S.x * 0.5, S.y * 0.5, S.z * 0.5);
        float d = sdRBox(p, hs - float3(0, 0, hs.z * 0.35), hs.z * 0.6);
        float2 n = saturate(1.0 - (p.xy * p.xy) / (hs.xy * hs.xy));
        d -= 0.03 * n.x * n.y;
        hmin(h, d * 0.85, matA, FPART(FP_BODY), obj);
        return;
    }
    if (kind == FK_BOOKS)
    {
        float y = 0.0;
        [unroll] for (int i = 0; i < 3; i++)
        {
            float hk = brHash01((uint)(i * 97 + (int)(seed * 1000.0)) + 3u);
            float th = lerp(0.028, 0.046, hk);
            float3 sz = float3(lerp(0.20, 0.27, frac(hk * 7.0)), th, lerp(0.15, 0.20, frac(hk * 13.0)));
            float3 p = rotY(q - float3(0, y + th * 0.5, 0), (hk - 0.5) * 0.4);
            hmin(h, sdRBox(p, sz * 0.5, 0.003), MAT_PAPER, FPART(FP_BOOK + i * 5 + 3), obj);
            y += th;
        }
        return;
    }
    if (kind == FK_VASE)
    {
        float t = saturate(q.y / 0.30);
        float r = 0.035 + 0.055 * sin(t * 3.14159 * 0.85 + 0.25) * (1.0 - 0.4 * t);
        float body = max(length(q.xz) - r, abs(q.y - 0.15) - 0.15) * 0.8;
        body = max(body, -max(length(q.xz) - (r - 0.006), -(q.y - 0.27)));
        hmin(h, body, matA, FPART(FP_BODY), obj);
        // its eucalyptus is a plant (br_plants.hlsli, called from furnitureModel with the trip)
        return;
    }
    if (kind == FK_LOGS)
    {
        float l1 = sdCapsuleSeg(q, float3(-0.25, 0.06, -0.03), float3(0.25, 0.06, 0.05), 0.055);
        float l2 = sdCapsuleSeg(q, float3(-0.22, 0.06, 0.09), float3(0.24, 0.07, -0.05), 0.05);
        float l3 = sdCapsuleSeg(q, float3(-0.18, 0.15, 0.02), float3(0.2, 0.16, 0.03), 0.048);
        hmin(h, min(min(l1, l2), l3), matA, FPART(FP_BODY), obj);
        float grate = sdRAabb(q, float3(-0.28, 0.0, -0.12), float3(0.28, 0.02, 0.14), 0.004);
        hmin(h, grate, MAT_BLACKMETAL, FPART(FP_METAL), obj);
        return;
    }
}

// Bounding radius of a piece around (0, size.y/2, 0) in local space -- generous for pieces that
// reach outside their nominal box (the arc lamp's arm, a pendant's cord).
float fkBoundRadius(int kind, int v, float3 S, float roomH, float y0)
{
    float r = length(S) * 0.5 + 0.05;
    if (kind == FK_FLOORLAMP && v == 0) r = 1.45;
    if (kind == FK_PENDANT) r = max(r, (roomH - y0) * 0.5 + 0.3);
    if (kind == FK_PLANT) r += 0.25;
    if (kind == FK_VASE) r = max(r, 0.56);     // its eucalyptus arches out and over
    return r;
}
// How far a piece reaches from its own vertical axis (the trip's twist stretches distance by it):
// the arc lamp's dome hangs 1.42 m out; a plant's leaves overhang its pot.
float fkRadialReach(int kind, int v, float3 S)
{
    float r = length(S.xz) * 0.5;
    if (kind == FK_FLOORLAMP && v == 0) r = 1.45;
    if (kind == FK_PLANT) r += 0.25;
    if (kind == FK_VASE) r = 0.27;
    return r;
}
float3 fkBoundCentre(int kind, int v, float3 S, float roomH, float y0)
{
    if (kind == FK_FLOORLAMP && v == 0) return float3(0, 1.0, 0.55);
    if (kind == FK_PENDANT) return float3(0, (roomH - y0) * 0.5, 0);
    return float3(0, S.y * 0.5, 0);
}

// Dispatch a piece by kind. q is in the piece's local frame.
// anim: the trip's (time, breathe, drift, geometry), the amounts already times the dose envelope.
// Only the plants move by it (br_plants.hlsli); every other piece is moved by its object warp.
void furnitureModel(float3 q, int kind, int v, float3 S, int matA, int matB, int obj, float seed, float roomH, float y0, float4 anim, inout SHit h)
{
    if (kind == FK_SOFA || kind == FK_CHAIR) seatModel(q, kind, v, S, matA, matB, obj, h);
    else if (kind == FK_COFFEE || kind == FK_SIDE) tableModel(q, kind, v, S, matA, matB, obj, h);
    else if (kind == FK_RUG) rugModel(q, S, obj, h);
    else if (kind == FK_FLOORLAMP || kind == FK_TABLELAMP || kind == FK_PENDANT) lampModel(q, kind, v, S, matA, matB, obj, roomH, y0, h);
    else if (kind == FK_SHELF) shelfModel(q, v, S, matA, obj, seed, h);
    else if (kind == FK_CONSOLE) consoleModel(q, S, matA, matB, obj, h);
    else if (kind == FK_PLANT) plantModel(q, v, S, matA, matB, obj, seed, anim, h);
    else if (kind == FK_ART) artModel(q, v, S, matA, matB, obj, h);
    else
    {
        smallModel(q, kind, v, S, matA, matB, obj, seed, h);
        if (kind == FK_VASE) plBouquet(q, seed, anim, matB, obj, h);
    }
}

#endif
