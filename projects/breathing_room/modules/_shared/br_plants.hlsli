// br_plants.hlsli -- the house plants: fiddle-leaf fig (v0), snake plant (v1), olive standard (v2).
// Included by br_furniture.hlsli (the distance field); shade.hlsl calls plantLeafCoords to shade
// a leaf in its own frame (midrib, veins, bands, margins).
//
// EVERY PART IS A REAL DISTANCE: capsules, round cones and 2D outlines extruded into thin
// slabs. The renderer does not only march onto a leaf. Its ambient-occlusion taps ask "how far is
// the nearest leaf?" from 2 to 45 cm away, and the old leaves -- flat ellipsoids with an
// approximate distance -- answered "very near" all along the planes they lay in. The wall behind
// the fig was streaked with occlusion fanning out of leaves that were nowhere near it.
//
// THE PLANTS GROW CONNECTED: pot, soil, trunk and branches (or a clump of blades), a petiole from
// the stem to every leaf blade. Leaves are numbered; part id FP_BOOK + n carries n, so shading can
// rebuild that leaf's frame from the same function the distance field uses.
//
// THE TRIP moves each plant its own way as the dose rises. `anim` = (trip time s, breathe, drift,
// geometry), each amount already multiplied by the dose envelope:
//   fig     leaves open and fold in a slow wave that climbs the trunk; the crown sways
//   snake   blades writhe: their twist winds and unwinds, and a ripple runs up each like a flame
//   olive   the crown breathes, and its leaves flicker in a wave that crosses it like a shoal
// and the GEOMETRY channel resolves each into a diagram of itself, its natural scatter pulled
// toward an ideal symmetry:
//   fig     the trunk straightens and every leaf is held level, in tiers round the golden spiral
//   snake   the clumps open into a twelve-fold rosette, every blade leaning and twisting alike
//   olive   the head becomes an even starburst of equal branches
// Each moves leaves rigidly (rotations about their stems) or bends a stem by a few centimetres,
// so the distance stays a bound; every leaf is still scaled by its Lipschitz margin.
#ifndef BR_PLANTS_HLSLI
#define BR_PLANTS_HLSLI

#define PL_FIG_LEAVES    30
#define PL_SNAKE_BLADES  12
#define PL_OLIVE_BRANCH  7
#define PL_OLIVE_PER     6

float plHash(float n) { return frac(sin(n * 127.1 + 31.7) * 43758.5453); }
float3 plDir(float a) { return float3(sin(a), 0.0, cos(a)); }

// 2D uneven capsule (exact): circle r1 at the origin, circle r2 at (0, h), joined by tangents
float plUnevenCapsule(float2 p, float r1, float r2, float h)
{
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(max(1.0 - b * b, 1e-4));
    float k = dot(p, float2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}
// 2D vesica (exact): pointed at both ends, half-length b along y, half-width w
float plVesica(float2 p, float b, float w)
{
    float r = (b * b + w * w) / (2.0 * w);
    float d = r - w;
    p = abs(p);
    return ((p.y - b) * d > p.x * b) ? length(p - float2(0.0, b)) : length(p - float2(-d, 0.0)) - r;
}
// a 2D outline extruded into a slab of half-thickness th (exact for an exact outline)
float plSlab(float d2, float y, float th)
{
    float2 w = float2(d2, abs(y) - th);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

// One leaf blade: where its petiole leaves the stem, where the blade begins, the blade's frame
// (ax across, ay the upper-side normal, az along the midrib) and its shape.
struct PLeaf
{
    float3 att, base;
    float3 ax, ay, az;
    float len, w1, w2, cup, droop;
};

PLeaf plFrame(float3 att, float3 base, float3 az, float roll, float len, float w1, float w2, float cup, float droop)
{
    PLeaf L;
    L.att = att; L.base = base; L.az = az;
    float3 ax0 = cross(float3(0, 1, 0), az);
    ax0 = (dot(ax0, ax0) > 1e-6) ? normalize(ax0) : float3(1, 0, 0);
    float3 ay0 = cross(az, ax0);
    float c = cos(roll), s = sin(roll);
    L.ax = ax0 * c + ay0 * s;
    L.ay = -ax0 * s + ay0 * c;
    L.len = len; L.w1 = w1; L.w2 = w2; L.cup = cup; L.droop = droop;
    return L;
}

// ---- FIDDLE-LEAF FIG ------------------------------------------------------------------------
// A trunk that leans and wanders a little, bare below 60 cm; two side branches; 24 violin
// leaves on petioles, spiralling at the golden angle, the young ones near the top held higher.
float plFigSway(float y, float H, float seed, float4 anim)
{
    float k = saturate(y / H);
    return anim.z * 0.055 * k * k * sin(anim.x * 0.55 + seed * 6.28);
}
float3 plFigTrunk(float y, float H, float seed, float4 anim)
{
    float wander = 1.0 - 0.85 * anim.w;
    return float3(0.035 * wander * sin(y * 2.1 + seed * 6.28) + plFigSway(y, H, seed, anim), y,
                  0.025 * wander * sin(y * 1.6 + seed * 4.10));
}
void plFigBranch(int b, float H, float seed, float4 anim, out float3 s, out float3 e)
{
    float yb = (b == 0) ? 0.95 : 1.20;
    float az = seed * 6.28 + ((b == 0) ? 1.1 : 4.0);
    s = plFigTrunk(yb, H, seed, anim);
    e = s + plDir(az) * 0.26 + float3(0.0, 0.24, 0.0);
    e.x += plFigSway(e.y, H, seed, anim) * 0.6;
}
PLeaf plFigLeaf(int i, float3 S, float seed, float4 anim)
{
    float H = S.y;
    float hi = plHash((float)i + seed * 31.0);
    float3 att, out1;
    float hf;
    if (i < 18)
    {
        float t = ((float)i + 0.5) / 18.0;
        float y = lerp(0.62, H - 0.24, t);
        float a = (float)i * 2.39996 + seed * 6.28;
        out1 = plDir(a);
        att = plFigTrunk(y, H, seed, anim) + out1 * 0.010;
        hf = t;
    }
    else
    {
        int b = (i < 24) ? 0 : 1;
        int j = i - ((b == 0) ? 18 : 24);
        float3 s, e;
        plFigBranch(b, H, seed, anim, s, e);
        float u = ((float)j + 0.8) / 6.2;
        float3 bd = normalize(e - s);
        float3 side = normalize(cross(bd, float3(0, 1, 0)));
        float sgn = ((j & 1) == 0) ? 1.0 : -1.0;
        out1 = normalize(side * sgn * 0.8 + float3(bd.x, 0.0, bd.z) * 0.6);
        att = lerp(s, e, u) + out1 * 0.006;
        hf = 0.55 + 0.4 * u;
    }
    // the petiole rises from the stem at ~40 degrees
    float3 base = att + (out1 * 0.766 + float3(0, 0.643, 0)) * (0.045 + 0.02 * hi);
    // younger leaves stand up, older ones droop; the trip opens and folds them in a wave that
    // climbs the plant
    // older leaves hang lower and every blade is turned on its midrib, so from the eye's height
    // the leaves show their faces instead of their edges
    float pitch = lerp(lerp(-0.65, 0.55, hf) + (hi - 0.5) * 0.5, 0.12, anim.w);
    pitch += anim.y * 0.32 * sin(anim.x * 0.9 - base.y * 3.2 + seed * 4.0);
    float3 az = normalize(out1 * cos(pitch) + float3(0, sin(pitch), 0));
    float len = (0.20 + 0.10 * saturate(1.0 - abs(hf - 0.65) * 1.6)) * lerp(0.85, 1.12, frac(hi * 7.3));
    return plFrame(att, base, az, (frac(hi * 13.1) - 0.5) * 1.8 * (1.0 - anim.w), len, len * 0.07, len * 0.33, 1.1, 0.8);
}
// The fiddle-leaf outline (x across, z from the petiole), in leaf lengths: a narrow wedge from the
// petiole into a small lower lobe, a waist, and a broad rounded upper lobe -- the violin. Unions of
// exact circles and a tapered wedge, the waist softened.
float plFigOutline(float2 p, float len)
{
    float lower = length(p - float2(0.0, 0.34 * len)) - 0.21 * len;
    float upper = length(p - float2(0.0, 0.64 * len)) - 0.33 * len;
    float wedge = plUnevenCapsule(p - float2(0.0, 0.02 * len), 0.025 * len, 0.15 * len, 0.26 * len);
    return min(sminK(lower, upper, 0.05 * len), wedge);
}
// its half-width at z (the widest of the parts there): the shading's leaf-across coordinate
float plFigHalfWidth(float z, float len)
{
    float lo = 0.21 * len, up = 0.33 * len;
    float a = sqrt(max(lo * lo - (z - 0.34 * len) * (z - 0.34 * len), 0.0));
    float b = sqrt(max(up * up - (z - 0.64 * len) * (z - 0.64 * len), 0.0));
    float w = lerp(0.025, 0.15, saturate((z - 0.02 * len) / (0.26 * len))) * len * step(z, 0.43 * len);
    return max(max(a, b), max(w, 0.004));
}
// a fig leaf's distance; lq = the point in the leaf's frame
float plFigBlade(float3 lq, PLeaf L, float seed)
{
    // the midrib droops toward the tip; the blade cups up toward its edges
    float y = lq.y + L.droop * lq.z * lq.z - L.cup * lq.x * lq.x;
    float d2 = plFigOutline(float2(lq.x, lq.z), L.len);
    // a softly waved margin
    d2 += 0.0022 * sin(lq.z * 48.0 + seed * 10.0);
    return plSlab(d2, y, 0.0015) * 0.84;
}

// ---- SNAKE PLANT --------------------------------------------------------------------------
// Twelve stiff sword blades in three clumps, each leaning out, curving and twisting a little,
// folded along its midline, widest a third of the way up and drawn to a sharp tip.
struct PBlade { float3 base; float az, lean, H, wmax, twist; };
PBlade plSnakeBlade(int j, float3 S, float seed, float4 anim, float soilY)
{
    PBlade B;
    float hj = plHash((float)j * 1.37 + seed * 17.0);
    int c = j / 4;
    float ca = seed * 6.28 + (float)c * 2.094;
    float3 cc = plDir(ca) * 0.055;
    float ja = ca + ((float)(j % 4) - 1.5) * 0.9 + (hj - 0.5) * 0.5;
    // the geometry channel opens the three clumps into one even twelve-fold rosette
    float g = anim.w;
    float jr = seed * 6.28 + (float)j * 0.5236;
    float dj = jr - ja;
    dj -= 6.2831853 * round(dj / 6.2831853);
    B.base = lerp(cc + plDir(ja) * 0.016, plDir(jr) * 0.03, g) + float3(0.0, soilY - 0.02, 0.0);
    ja += dj * g;
    B.az = ja;
    B.lean = lerp(0.07 + 0.16 * frac(hj * 5.1) + ((j % 4 == 1 || j % 4 == 2) ? -0.05 : 0.04), 0.36, g);
    B.H = lerp(lerp(0.48, 0.86, frac(hj * 3.7)), 0.70, g * 0.7) * (S.y / 0.88);
    B.wmax = lerp(0.026, 0.040, frac(hj * 11.3));
    B.twist = lerp(lerp(0.3, 1.3, frac(hj * 2.9)) * ((frac(hj * 9.7) > 0.5) ? 1.0 : -1.0), 1.0, g);
    // the trip winds and unwinds them
    B.twist += anim.y * 1.1 * sin(anim.x * 0.7 + (float)j * 1.9);
    return B;
}
// the blade's own frame: x across, y up its spine (0..H), z through its thickness
float3 plSnakeLocal(float3 q, PBlade B, float4 anim, int j, out float t, out float w)
{
    float3 p = q - B.base;
    float c = cos(B.az), s = sin(B.az);
    // the lean direction onto +x, then the tilted spine onto +y
    float3 p1 = float3(c * p.z + s * p.x, p.y, -s * p.z + c * p.x);
    float cl = cos(B.lean), sl = sin(B.lean);
    float3 p2 = float3(cl * p1.x - sl * p1.y, sl * p1.x + cl * p1.y, p1.z);
    t = saturate(p2.y / B.H);
    // a ripple climbs each blade like a flame (the trip), and the spine bows back a little
    p2.x -= anim.z * 0.022 * t * sin(t * 5.0 - anim.x * 1.3 + (float)j * 2.3) - 0.05 * t * t * B.H;
    float tw = B.twist * t;
    float ct = cos(tw), st = sin(tw);
    float3 p3 = float3(ct * p2.x - st * p2.z, p2.y, st * p2.x + ct * p2.z);
    w = B.wmax * min(0.55 + 1.6 * t, 1.0) * pow(saturate((1.0 - t) / 0.68), 0.8);
    return p3;
}
float plSnakeDist(float3 p3, float t, float w, float H)
{
    // folded along the midline into a shallow V
    float z = p3.z - 4.0 * p3.x * p3.x;
    float d2 = sdBox2(float2(p3.x, z), float2(max(w, 0.0005), 0.0022));
    return max(d2, max(-p3.y - 0.02, p3.y - H)) * 0.84;
}

// ---- OLIVE STANDARD -----------------------------------------------------------------------
// A clear stem to a round head: seven branches out of the top of the trunk, six narrow
// lance-shaped leaves on each in alternate pairs.
float3 plOliveTrunk(float y, float seed)
{
    return float3(0.02 * sin(y * 4.0 + seed * 6.28), y, 0.015 * sin(y * 3.1 + seed * 3.0));
}
void plOliveBranch(int b, float3 S, float seed, float4 anim, out float3 s, out float3 m, out float3 e)
{
    float top = S.y - 0.42;
    s = plOliveTrunk(top, seed);
    float hb = plHash((float)b * 3.3 + seed * 13.0);
    float az = (float)b * 2.39996 + seed * 6.28;
    float rise = lerp(-0.05, 0.22, frac(hb * 5.7));
    float reach = lerp(0.20, 0.28, hb);
    // the geometry channel evens the head into a starburst: equal branches at equal angles,
    // rising and falling in turn
    float g = anim.w;
    float da = ((float)b * 0.8976 + seed * 6.28) - az;
    da -= 6.2831853 * round(da / 6.2831853);
    az += da * g;
    rise = lerp(rise, ((b & 1) == 0) ? -0.02 : 0.20, g);
    reach = lerp(reach, 0.25, g);
    // the head breathes (the trip)
    float breathe = 1.0 + anim.y * 0.06 * sin(anim.x * 0.5);
    e = s + (plDir(az) * reach + float3(0.0, 0.16 + rise, 0.0)) * breathe;
    m = lerp(s, e, 0.5) + float3(0.0, 0.04, 0.0);
}
PLeaf plOliveLeaf(int i, float3 S, float seed, float4 anim)
{
    int b = i / PL_OLIVE_PER, j = i % PL_OLIVE_PER;
    float3 s, m, e;
    plOliveBranch(b, S, seed, anim, s, m, e);
    float u = 0.38 + 0.62 * ((float)(j / 2) + 0.5) / 3.0;
    float3 att = (u < 0.5) ? lerp(s, m, u * 2.0) : lerp(m, e, u * 2.0 - 1.0);
    float3 bd = normalize(e - s);
    float3 side = cross(bd, float3(0, 1, 0));
    side = (dot(side, side) > 1e-6) ? normalize(side) : float3(1, 0, 0);
    float sgn = ((j & 1) == 0) ? 1.0 : -1.0;
    float hi = plHash((float)i * 2.1 + seed * 7.0);
    // leaves angle forward along the twig and out to its sides; the trip sets them flickering
    // in a wave that crosses the head
    float ang = lerp(0.62 + (hi - 0.5) * 0.3, 0.70, anim.w) + anim.z * 0.45 * sin(anim.x * 1.1 - dot(att, float3(6.0, 3.0, 4.0)));
    float3 az = normalize(bd * cos(ang) + side * sgn * sin(ang) + float3(0, 0.15, 0));
    float len = lerp(0.050, 0.068, hi);
    return plFrame(att, att, az, (frac(hi * 5.3) - 0.5) * 0.8 * (1.0 - anim.w), len, 0.0, len * 0.11, 9.0, 1.5);
}
float plOliveBlade(float3 lq, PLeaf L)
{
    float y = lq.y + L.droop * lq.z * lq.z - L.cup * lq.x * lq.x;
    float d2 = plVesica(float2(lq.x, lq.z - L.len * 0.5), L.len * 0.5, L.w2);
    return plSlab(d2, y, 0.0008) * 0.86;
}

// ---- EUCALYPTUS IN THE VASE -----------------------------------------------------------------
// Four arching stems of silver-dollar eucalyptus: round juvenile leaves in opposite pairs, each
// pair turned a quarter from the last, every leaf clasping its stem. The trip sways the stems
// and sets the coins turning on them.
#define PL_EU_STEMS 6
#define PL_EU_NODES 6
float3 plEuStem(int s, float t, float seed, float4 anim)
{
    float hs = plHash((float)s * 2.7 + seed * 5.0);
    float a = (float)s * 1.0472 + seed * 6.28 + 0.4 + (hs - 0.5) * 0.5;
    float3 d = plDir(a);
    float H = 0.34 + 0.20 * hs;
    float reach = 0.07 + 0.13 * frac(hs * 3.3);
    // up out of the mouth, then out and over
    float3 P0 = float3(0.0, 0.20, 0.0) + d * 0.01;
    float3 P1 = float3(0.0, 0.20 + H * 0.75, 0.0) + d * reach * 0.3;
    float3 P2 = float3(0.0, 0.17 + H, 0.0) + d * reach;
    float3 sw = plDir(a + 1.5708) * (anim.z * 0.03 * sin(anim.x * 0.8 + (float)s * 2.1));
    P1 += sw * 0.4; P2 += sw;
    float u = 1.0 - t;
    return u * u * P0 + 2.0 * u * t * P1 + t * t * P2;
}
// leaf n (= stem * 10 + node * 2 + side) of the bouquet: its frame and radius
PLeaf plEuLeaf(int n, float seed, float4 anim)
{
    int s = n / (PL_EU_NODES * 2), k = (n / 2) % PL_EU_NODES;
    float side = ((n & 1) == 0) ? 1.0 : -1.0;
    float t = 0.30 + 0.14 * (float)k;
    float3 P = plEuStem(s, t, seed, anim);
    float3 T = normalize(plEuStem(s, min(t + 0.02, 1.0), seed, anim) - plEuStem(s, t - 0.02, seed, anim));
    float3 D = cross(T, float3(0, 1, 0));
    D = (dot(D, D) > 1e-6) ? normalize(D) : float3(1, 0, 0);
    if ((k & 1) == 1) D = cross(T, D);
    D *= side;
    float3 N = cross(D, T);
    // the coins turn on their stems (the trip)
    float ph = anim.y * 0.7 * sin(anim.x * 1.3 + (float)s * 1.7 + (float)k * 0.9 + side);
    float cp = cos(ph), sp = sin(ph);
    float r = lerp(0.027, 0.012, (float)k / (float)(PL_EU_NODES - 1)) * lerp(0.85, 1.1, plHash((float)n * 1.3 + seed));
    PLeaf L;
    L.att = P; L.base = P + D * r * 0.75;
    L.ax = D; L.az = T * cp + N * sp; L.ay = N * cp - T * sp;
    L.len = r; L.w1 = 0.0; L.w2 = r; L.cup = 2.0; L.droop = 0.0;
    return L;
}
void plBouquet(float3 q, float seed, float4 anim, int matB, int obj, inout SHit h)
{
    float stems = 1e9, best = 1e9;
    int bi = 0;
    [loop] for (int s = 0; s < PL_EU_STEMS; s++)
    {
        float3 a0 = plEuStem(s, 0.0, seed, anim), a1 = plEuStem(s, 0.34, seed, anim);
        float3 a2 = plEuStem(s, 0.67, seed, anim), a3 = plEuStem(s, 1.0, seed, anim);
        stems = min(stems, min(sdRoundCone(q, a0, a1, 0.0028, 0.0024), min(sdRoundCone(q, a1, a2, 0.0024, 0.0019), sdRoundCone(q, a2, a3, 0.0019, 0.0014))));
        // the stem's leaves only where they can be nearer than what is already found
        if (sdCapsuleSeg(q, a0, a3, 0.06) < min(best, h.d))
        {
            [loop] for (int j = 0; j < PL_EU_NODES * 2; j++)
            {
                PLeaf L = plEuLeaf(s * PL_EU_NODES * 2 + j, seed, anim);
                float3 p = q - L.base;
                float3 lq = float3(dot(p, L.ax), dot(p, L.ay), dot(p, L.az));
                float d = plSlab(length(lq.xz) - L.len, lq.y - L.cup * dot(lq.xz, lq.xz), 0.0008) * 0.85;
                if (d < best) { best = d; bi = s * PL_EU_NODES * 2 + j; }
            }
        }
    }
    hmin(h, stems, MAT_WALNUT, FPART(FP_LEG), obj);
    // 72 coins share the 48 leaf part ids (they only vary a coin's tone)
    hmin(h, best, matB, FPART(FP_BOOK + bi % 48), obj);
}

// ---- THE MODEL ------------------------------------------------------------------------------
float plPot(float3 q, float rTop, float rBot, float hgt, out float soil)
{
    float t = saturate(q.y / hgt);
    float r = lerp(rBot, rTop, t);
    float body = max(length(q.xz) - r, abs(q.y - hgt * 0.5) - hgt * 0.5);
    float rim = sdTorusY(q - float3(0, hgt - 0.012, 0), rTop - 0.006, 0.018);
    soil = max(length(q.xz) - (rTop - 0.02), abs(q.y - (hgt - 0.05)) - 0.004);
    float inner = max(length(q.xz) - (rTop - 0.022), -(q.y - (hgt - 0.05)));
    return max(min(body, rim), -inner);
}

void plantModel(float3 q, int v, float3 S, int matA, int matB, int obj, float seed, float4 anim, inout SHit h)
{
    float soil;
    float potH = (v == 1) ? 0.30 : 0.36;
    float pot = plPot(q, (v == 1) ? 0.15 : 0.20, (v == 1) ? 0.12 : 0.15, potH, soil);
    hmin(h, pot, matB, FPART(FP_POT), obj);
    hmin(h, soil, MAT_TERRACOTTA, FPART(FP_SOIL), obj);
    float soilY = potH - 0.05;
    if (v == 1)
    {
        float best = 1e9; int bi = 0;
        [loop] for (int j = 0; j < PL_SNAKE_BLADES; j++)
        {
            PBlade B = plSnakeBlade(j, S, seed, anim, soilY);
            // a capsule round the whole blade: only blades that can be nearer are measured
            float3 tip = B.base + float3(sin(B.lean) * sin(B.az), cos(B.lean), sin(B.lean) * cos(B.az)) * B.H;
            float bound = sdCapsuleSeg(q, B.base, tip, B.wmax + 0.06 + 0.06 * B.H);
            if (bound < min(best, h.d))
            {
                float t, w;
                float3 p3 = plSnakeLocal(q, B, anim, j, t, w);
                // the ripple (drift) and the winding (breathe) shear the blade: past a full trip
                // (overdrive) the 0.84 margin no longer covers them
                float d = plSnakeDist(p3, t, w, B.H) / (1.0 + 0.2 * max(max(anim.y, anim.z) - 1.0, 0.0));
                if (d < best) { best = d; bi = j; }
            }
        }
        hmin(h, best, matA, FPART(FP_BOOK + bi), obj);
        return;
    }
    if (v == 0)
    {
        // the trunk: four round cones along its wandering centreline, and two branches
        float H = S.y;
        float ys[5] = { soilY - 0.04, 0.62, 1.00, 1.35, H - 0.20 };
        float rs[5] = { 0.021, 0.016, 0.013, 0.010, 0.006 };
        float wood = 1e9;
        [unroll] for (int k = 0; k < 4; k++)
            wood = min(wood, sdRoundCone(q, plFigTrunk(ys[k], H, seed, anim), plFigTrunk(ys[k + 1], H, seed, anim), rs[k], rs[k + 1]));
        [unroll] for (int b = 0; b < 2; b++)
        {
            float3 s, e;
            plFigBranch(b, H, seed, anim, s, e);
            wood = min(wood, sdRoundCone(q, s, e, 0.0085, 0.005));
        }
        hmin(h, wood, MAT_WALNUT, FPART(FP_LEG), obj);
        float best = 1e9; int bi = 0;
        [loop] for (int i = 0; i < PL_FIG_LEAVES; i++)
        {
            PLeaf L = plFigLeaf(i, S, seed, anim);
            float3 c = L.base + L.az * (L.len * 0.5);
            if (length(q - c) - L.len * 0.62 - 0.06 < min(best, h.d))
            {
                float3 p = q - L.base;
                float3 lq = float3(dot(p, L.ax), dot(p, L.ay), dot(p, L.az));
                float d = min(plFigBlade(lq, L, seed), sdCapsuleSeg(q, L.att, L.base + L.az * 0.01, 0.0032));
                if (d < best) { best = d; bi = i; }
            }
        }
        hmin(h, best, matA, FPART(FP_BOOK + bi), obj);
        return;
    }
    // v == 2: the olive standard
    {
        float top = S.y - 0.42;
        float wood = sdRoundCone(q, plOliveTrunk(soilY - 0.04, seed), plOliveTrunk(top * 0.55, seed), 0.022, 0.018);
        wood = min(wood, sdRoundCone(q, plOliveTrunk(top * 0.55, seed), plOliveTrunk(top, seed), 0.018, 0.013));
        float best = 1e9; int bi = 0;
        [loop] for (int b = 0; b < PL_OLIVE_BRANCH; b++)
        {
            float3 s, m, e;
            plOliveBranch(b, S, seed, anim, s, m, e);
            float twig = min(sdRoundCone(q, s, m, 0.009, 0.006), sdRoundCone(q, m, e, 0.006, 0.0025));
            wood = min(wood, twig);
            // the branch's leaves only where they can be nearer than what is already found
            if (twig - 0.10 < min(best, min(wood, h.d)))
            {
                [loop] for (int j = 0; j < PL_OLIVE_PER; j++)
                {
                    int i = b * PL_OLIVE_PER + j;
                    PLeaf L = plOliveLeaf(i, S, seed, anim);
                    float3 p = q - L.base;
                    float3 lq = float3(dot(p, L.ax), dot(p, L.ay), dot(p, L.az));
                    float d = plOliveBlade(lq, L);
                    if (d < best) { best = d; bi = i; }
                }
            }
        }
        hmin(h, wood, MAT_WALNUT, FPART(FP_LEG), obj);
        hmin(h, best, matA, FPART(FP_BOOK + bi), obj);
    }
}

// Leaf-local coordinates for shading: uv.x across the blade (-1 edge .. 0 midline .. 1 edge),
// uv.y along it (0 base .. 1 tip), up = +1 on the upper side. False when q is not on a blade.
bool plantLeafCoords(int v, float3 S, float seed, float4 anim, int n, float3 q, float3 nrm, out float2 uv, out float up)
{
    uv = 0; up = 1.0;
    if (v == 1)
    {
        float soilY = 0.30 - 0.05;
        PBlade B = plSnakeBlade(clamp(n, 0, PL_SNAKE_BLADES - 1), S, seed, anim, soilY);
        float t, w;
        float3 p3 = plSnakeLocal(q, B, anim, n, t, w);
        uv = float2(p3.x / max(w, 1e-3), t);
        return true;
    }
    PLeaf L;
    if (v == 0) L = plFigLeaf(clamp(n, 0, PL_FIG_LEAVES - 1), S, seed, anim);
    else L = plOliveLeaf(clamp(n, 0, PL_OLIVE_BRANCH * PL_OLIVE_PER - 1), S, seed, anim);
    float3 p = q - L.base;
    float3 lq = float3(dot(p, L.ax), dot(p, L.ay), dot(p, L.az));
    float t = lq.z / max(L.len, 1e-3);
    // half-width of the outline at this point along it (the capsule's tangent lines / the vesica)
    float hw = (v == 0) ? plFigHalfWidth(lq.z, L.len)
                        : L.w2 * sqrt(saturate(1.0 - (2.0 * t - 1.0) * (2.0 * t - 1.0)));
    uv = float2(lq.x / max(hw, 1e-3), t);
    up = (dot(nrm, L.ay) >= 0.0) ? 1.0 : -1.0;
    return lq.z > -0.004;
}

#endif
