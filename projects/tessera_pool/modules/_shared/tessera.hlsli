// tessera.hlsli — the shared contract for tessera_pool.
//
// Everything in this file is a DEFINITION every node in the show must agree on: the record
// layout TP_Plan publishes, the coordinate systems, the unfolded caustic atlas, and the tile
// function. Nothing here decides anything; TP_Plan decides, this file only says how the
// decision is spelled.
//
// TANK SPACE (world units, the space the internal camera flies in)
//   x  right      interior [-hx, +hx]
//   y  up         floor at -depth, STILL WATER AT y = 0, glass rim at +freeboard
//   z  toward the viewer, interior [-hz, +hz]
//   glass shell of thickness `thick` wrapped around the interior on all four sides and below
//
// FOOTPRINT SPACE (normalized) is what ripple sources are stored in: fx, fz in [-1, 1] mapping
// to the interior extents. Stored normalized on purpose — changing the basin proportions then
// cannot throw a hand-placed source outside the tank, which is the one edit the user is most
// likely to lose.
#ifndef TESSERA_HLSLI
#define TESSERA_HLSLI

// ---------------------------------------------------------------------------
// The record. 20 floats / 80 bytes. One buffer, role-discriminated.
// ---------------------------------------------------------------------------
struct TpRec
{
    float3 pos;      // src: (fx, 0, fz) footprint  | tank: (pattern, tileVar, gloss) | light: sun dir
    float3 dims;     // tank: (hx, depth, hz)       | src: (radius, 0, 0)
    float  role;
    float  kind;     // src: 0 drop / 1 emitter / 2 swell
    float3 tint;     // palette swatch, grout colour, sun colour
    float  seed;
    float  p0;       // src amplitude | tank glass thickness | light intensity
    float  p1;       // src period    | tank freeboard       | light sky level
    float  p2;       // src wavelength| tank tile pitch      | light caustic gain
    float  p3;       // src decay     | tank grout width     | light spec power
    float  flags;
    float  active;
    float  pad0;
    float  pad1;
};

#define TP_HEADER 0u
#define TP_TANK   1u
#define TP_LIGHT  2u
#define TP_PAL_0  3u
#define TP_PALS   6u
#define TP_SRC_0  9u
#define TP_SRCS   16u
#define TP_COUNT  25u

#define ROLE_HEADER 0.0
#define ROLE_TANK   1.0
#define ROLE_LIGHT  2.0
#define ROLE_PAL    3.0
#define ROLE_SRC    4.0

#define KIND_DROP  0.0
#define KIND_EMIT  1.0
#define KIND_SWELL 2.0

#define F_EDITED   1u
#define F_SELECTED 2u

// ---------------------------------------------------------------------------
// Hashing. Integer-bit mixing, never frac(sin(x)) — a sin hash biases badly once the seed
// grows past a few hundred, which shows up as a weighted draw quietly refusing to pick one of
// its options.
// ---------------------------------------------------------------------------
uint tpHashU(uint x)
{
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}
float tpH1(uint a) { return (float)(tpHashU(a) & 0x00FFFFFFu) * (1.0 / 16777216.0); }

// Value noise on the same integer mixer. Used for glaze mottle and for cast-stone grain — both
// want a CONTINUOUS field, not the per-cell draws above, so this interpolates a lattice.
float tpHash2(float2 i)
{
    uint x = (uint)(i.x + 8192.0);
    uint y = (uint)(i.y + 8192.0);
    return tpH1(tpHashU(x * 374761393u) ^ tpHashU(y * 668265263u));
}

float tpVNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = tpHash2(i);
    float b = tpHash2(i + float2(1.0, 0.0));
    float c = tpHash2(i + float2(0.0, 1.0));
    float d = tpHash2(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float tpRnd(float a, float b)
{
    return tpH1(tpHashU(asuint(a * 1.0 + 12.3456)) ^ (tpHashU(asuint(b * 1.0 + 78.9012)) * 2654435761u));
}
float tpRnd2(uint i, float salt) { return tpH1(tpHashU(i * 747796405u + 2891336453u) ^ tpHashU(asuint(salt + 3.7))); }

// ---------------------------------------------------------------------------
// Tank accessors. Every node reads its geometry through these so a basin change lands
// everywhere at once.
// ---------------------------------------------------------------------------
float3 tpTankHalf(TpRec t)  { return float3(t.dims.x, t.dims.y, t.dims.z); }   // (hx, depth, hz)
float  tpTankThick(TpRec t) { return t.p0; }
float  tpTankFree(TpRec t)  { return t.p1; }
float  tpTankPitch(TpRec t) { return t.p2; }
float  tpTankGrout(TpRec t) { return t.p3; }

// footprint (-1..1) -> world xz
float2 tpFootToWorld(float2 f, TpRec t) { return float2(f.x * t.dims.x, f.y * t.dims.z); }
float2 tpWorldToFoot(float2 w, TpRec t) { return float2(w.x / max(t.dims.x, 1e-4), w.y / max(t.dims.z, 1e-4)); }

// footprint (-1..1) -> simulation uv (0..1). The sim grid covers exactly the interior footprint.
float2 tpFootToSim(float2 f) { return f * 0.5 + 0.5; }
float2 tpSimToFoot(float2 u) { return u * 2.0 - 1.0; }

// ---------------------------------------------------------------------------
// The caustic atlas: the tank interior UNFOLDED. Floor in the middle, the four walls hinged
// outward around it, so one texture carries every surface the refracted sun can reach and the
// node's own preview reads as a plan of the tank rather than as an abstract lightmap.
//
//   +---------+---------+---------+
//   |         |  -Z wall|         |
//   +---------+---------+---------+
//   | -X wall |  FLOOR  | +X wall |
//   +---------+---------+---------+
//   |         |  +Z wall|         |
//   +---------+---------+---------+
// ---------------------------------------------------------------------------
#define TP_FACE_FLOOR 0
#define TP_FACE_NX    1
#define TP_FACE_PX    2
#define TP_FACE_NZ    3
#define TP_FACE_PZ    4

// The floor takes the central HALF and each wall an outer quarter — exact fractions on
// purpose. A 2048-sample grid then maps onto the floor's 256 bins at exactly 8 samples per
// bin, so every bin receives the same number and there is no beat between the two lattices.
// The earlier 0.28/0.72 split gave 9.09 samples per bin and painted a diagonal moire across
// the whole floor that no amount of sample jitter could remove.
#define TP_A_LO 0.000
#define TP_A_C0 0.250
#define TP_A_C1 0.750
#define TP_A_HI 1.000

float2 tpAtlasUV(float3 p, int face, float3 half3)
{
    float fx = saturate(p.x / max(half3.x, 1e-4) * 0.5 + 0.5);
    float fz = saturate(p.z / max(half3.z, 1e-4) * 0.5 + 0.5);
    float fy = saturate(-p.y / max(half3.y, 1e-4));            // 0 at the waterline, 1 on the floor

    if (face == TP_FACE_FLOOR) return float2(lerp(TP_A_C0, TP_A_C1, fx), lerp(TP_A_C0, TP_A_C1, fz));
    if (face == TP_FACE_NX)    return float2(lerp(TP_A_C0, TP_A_LO, fy), lerp(TP_A_C0, TP_A_C1, fz));
    if (face == TP_FACE_PX)    return float2(lerp(TP_A_C1, TP_A_HI, fy), lerp(TP_A_C0, TP_A_C1, fz));
    if (face == TP_FACE_NZ)    return float2(lerp(TP_A_C0, TP_A_C1, fx), lerp(TP_A_C0, TP_A_LO, fy));
    return                            float2(lerp(TP_A_C0, TP_A_C1, fx), lerp(TP_A_C1, TP_A_HI, fy));
}

// Which region an atlas texel belongs to, and the WORLD AREA that region covers. The resolve
// pass needs both: a floor bin and a wall bin subtend different world areas, so a raw photon
// count is not an irradiance until it has been divided by the area its bin actually stands for.
int tpAtlasRegion(float2 uv, float3 half3, out float worldArea, out float atlasArea)
{
    bool cx = (uv.x >= TP_A_C0 && uv.x <= TP_A_C1);
    bool cy = (uv.y >= TP_A_C0 && uv.y <= TP_A_C1);
    float sc = TP_A_C1 - TP_A_C0;
    float sw = TP_A_C0 - TP_A_LO;

    if (cx && cy)  { worldArea = (2.0 * half3.x) * (2.0 * half3.z); atlasArea = sc * sc; return TP_FACE_FLOOR; }
    if (cy && uv.x < TP_A_C0) { worldArea = half3.y * (2.0 * half3.z); atlasArea = sw * sc; return TP_FACE_NX; }
    if (cy && uv.x > TP_A_C1) { worldArea = half3.y * (2.0 * half3.z); atlasArea = sw * sc; return TP_FACE_PX; }
    if (cx && uv.y < TP_A_C0) { worldArea = half3.y * (2.0 * half3.x); atlasArea = sw * sc; return TP_FACE_NZ; }
    if (cx && uv.y > TP_A_C1) { worldArea = half3.y * (2.0 * half3.x); atlasArea = sw * sc; return TP_FACE_PZ; }

    worldArea = 1.0; atlasArea = 1.0;
    return -1;                                                  // the four dead corner cells
}

// ---------------------------------------------------------------------------
// The mosaic lining. One function, so the renderer's tiles and the plan canvas's tile grid can
// never disagree about pitch, offset or palette.
//
// `q` is the surface coordinate ON THAT FACE, in world units, with a per-face origin chosen so
// the grid runs continuously around the inside of the tank.
// ---------------------------------------------------------------------------
float2 tpFaceCoord(float3 p, int face, float3 half3)
{
    if (face == TP_FACE_FLOOR) return float2(p.x, p.z);
    if (face == TP_FACE_NX || face == TP_FACE_PX) return float2(p.z, p.y);
    return float2(p.x, p.y);
}

// Face-tangent basis. MUST agree with tpFaceCoord above — this is the inverse of it, and any
// disagreement shows up as tile relief lit from the wrong side on two of the five faces.
float3 tpFaceTangent(int face, float2 v)
{
    if (face == TP_FACE_FLOOR) return float3(v.x, 0.0, v.y);
    if (face == TP_FACE_NX || face == TP_FACE_PX) return float3(0.0, v.y, v.x);
    return float3(v.x, v.y, 0.0);
}

struct TpTile
{
    float3 albedo;
    float  grout;      // 1 inside the grout line, 0 on the tile face
    float2 local;      // -1..1 within the tile, for the bevel
    float2 tilt;       // face-tangent slope from this tile sitting off true
    float  gloss;
};

// The four things that separate "six flat colours in a grid" from fired ceramic. Grouped into a
// struct so the tile function keeps one call shape as the finish gains knobs.
struct TpTileFinish
{
    float mottle;      // depth of the in-glaze colour cloud
    float tilt;        // how far a hand-laid tile sits off true, as a tangent slope
    float glossVar;    // spread of per-tile glaze gloss; a real sheet fires unevenly
    float edgeAO;      // contact darkening into the grout line
};

// `filt` is the WORLD-SPACE WIDTH OF THE SAMPLE FOOTPRINT at this point — how much lining one
// screen pixel covers. It is not optional polish.
//
// A mosaic has infinitely sharp edges, and a refracted lookup is a single point sample whose
// footprint is magnified enormously by the water surface. Sampled unfiltered, every tile
// boundary crawls and flickers with the tiniest residual motion in the surface — the whole
// image reads as violent jitter while the water itself is nearly still, and no amount of
// damping can touch it because the water is not what is moving. Widening the edges to the
// footprint, and fading toward the palette mean once one pixel covers more than a tile, is
// texture filtering done by hand because a compute shader has no derivatives to do it with.
TpTile tpTile(float2 q, float pitch, float groutFrac, float variance, float tileSeed,
              int pattern, float3 pal[6], float3 groutCol, float filt, TpTileFinish fin)
{
    TpTile o;
    pitch = max(pitch, 0.004);

    float2 cell = q / pitch;
    float rowShift = 0.0;

    if (pattern == 1)                       // Running Bond — half-offset alternate rows, wide tiles
    {
        cell.x *= 0.5;
        rowShift = (fmod(floor(cell.y) + 64.0, 2.0) < 0.5) ? 0.0 : 0.5;
        cell.x += rowShift;
    }
    else if (pattern == 2)                  // Penny Round — offset rows, circular faces
    {
        rowShift = (fmod(floor(cell.y) + 64.0, 2.0) < 0.5) ? 0.0 : 0.5;
        cell.x += rowShift;
    }

    float2 id = floor(cell);
    float2 f  = frac(cell);
    o.local = f * 2.0 - 1.0;

    // per-tile identity
    uint h = tpHashU(asuint(id.x + 512.0) * 73856093u ^ tpHashU(asuint(id.y + 512.0) * 19349663u)
                     ^ tpHashU(asuint(tileSeed + 5.0)));
    float r0 = (float)(h & 0xFFFFu) * (1.0 / 65536.0);
    float r1 = (float)((h >> 8) & 0xFFFFu) * (1.0 / 65536.0);
    float r2 = (float)((h >> 16) & 0xFFFFu) * (1.0 / 65536.0);

    // A SECOND independent draw. The finish must not correlate with the colour: reusing r1/r2
    // would tie "how far this tile sits off true" to "how light it is", and the wall would come
    // out with all its dark tiles tipped the same way — a pattern the eye finds immediately.
    uint  h2 = tpHashU(h ^ 0x9E3779B9u);
    float r3 = (float)(h2 & 0xFFFFu) * (1.0 / 65536.0);
    float r4 = (float)((h2 >> 8) & 0xFFFFu) * (1.0 / 65536.0);
    float r5 = (float)((h2 >> 16) & 0xFFFFu) * (1.0 / 65536.0);

    // Banded: the palette index follows the row, so the lining reads as horizontal courses
    // instead of confetti. Everything else draws the index per tile.
    float sel = (pattern == 3) ? frac(tpH1(tpHashU(asuint(id.y + 96.0)) ^ tpHashU(asuint(tileSeed))) + r0 * 0.22)
                               : r0;
    int pi = clamp((int)(sel * 6.0), 0, 5);
    float3 base = pal[pi];

    // Value jitter is what stops six flat colours reading as six flat colours. Multiplicative,
    // so a dark swatch stays dark and the palette's own value hierarchy survives.
    float v = lerp(1.0, lerp(0.62, 1.34, r1), saturate(variance));
    float3 alb = base * v;

    // a few tiles carry a faint second hue, the way a real mosaic sheet does
    alb = lerp(alb, alb.zxy * 0.9 + 0.05, step(0.93, r2) * saturate(variance) * 0.5);

    // Edge softness is at least the footprint, expressed in cell units.
    float soft = saturate(filt / max(pitch, 1e-4));

    // ---- THE FINISH ---------------------------------------------------------------------
    //
    // Everything from here down is high-frequency, so ALL of it fades with the footprint on the
    // same schedule as the tile edges. Detail that outlives the point where one pixel covers a
    // whole tile is not detail, it is noise — and it is noise that CRAWLS, because under a
    // rippled surface the point being sampled moves every frame. This one factor is the
    // difference between a texture and a boil.
    float dfade = saturate(1.0 - soft * 2.5);

    // Glaze mottle. Two octaves of cloud in FACE space rather than tile space, so it drifts
    // across the joints the way a fired glaze does instead of stamping the same patch into every
    // tile; the per-tile offset then breaks the repeat that face-space alone would leave.
    float2 mp = cell * 3.1 + float2(r1, r2) * 11.0;
    float mott = tpVNoise(mp) * 0.66 + tpVNoise(mp * 2.7 + 19.3) * 0.34;
    alb *= lerp(1.0, 0.74 + 0.52 * mott, saturate(fin.mottle) * dfade);

    // Hand-laid tiles do not sit on one plane. This is the term that makes a mosaic sparkle in
    // PIECES instead of flashing as a single sheet, and it is most of why a real wall reads as
    // thousands of separate objects rather than as a printed grid with a highlight on it.
    o.tilt = (float2(r3, r4) - 0.5) * 2.0 * fin.tilt * dfade;

    // Cement is not a flat colour either, and a perfectly even joint is a giveaway.
    float3 gcol = groutCol * lerp(1.0, 0.84 + 0.30 * tpVNoise(cell * 7.3 + 3.1), dfade);

    float g, d;
    if (pattern == 2)                       // circular faces: grout is everything outside the disc
    {
        d = length(f - 0.5) * 2.0;
        float w = max(max(groutFrac, 0.02) * 1.6, soft * 2.0);
        g = smoothstep(1.0 - w, 1.0 + w * 0.25, d);
    }
    else
    {
        float2 e = abs(f - 0.5) * 2.0;
        d = max(e.x, e.y);
        float lo = 1.0 - max(max(groutFrac, 0.01) * 1.3, soft * 2.0);
        float hi = 1.0 - max(max(groutFrac, 0.01) * 0.35, soft * 0.5);
        g = smoothstep(lo, max(hi, lo + 1e-4), d);
    }

    // Contact darkening. The glaze rolls off into the joint and the joint is occluded by the two
    // tiles standing over it, so the last stretch before the grout is never at full value.
    alb *= 1.0 - saturate(fin.edgeAO) * 0.55 * smoothstep(0.30, 1.0, d) * dfade;

    o.grout  = g;
    o.albedo = lerp(alb, gcol, g);

    // Once a pixel covers a whole tile there is no tile left to resolve — resolve to the mean
    // instead of to whichever tile the point sample happened to land in, which is what makes an
    // unfiltered mosaic boil.
    float3 mean = (pal[0] + pal[1] + pal[2] + pal[3] + pal[4] + pal[5]) * (1.0 / 6.0);
    mean = lerp(mean, groutCol, saturate(groutFrac * 1.2));
    o.albedo = lerp(o.albedo, mean, saturate(soft - 0.55));

    // Per-tile glaze. A real sheet fires unevenly — some tiles come out near-mirror, some come
    // out satin — and that variation is what lets a bank of ceiling strips land on a mosaic as
    // scattered individual glints instead of as one flat sheen laid over the whole wall.
    o.gloss  = lerp(1.0, 0.25, g) * lerp(1.0 - saturate(fin.glossVar) * 0.85,
                                         1.0 + saturate(fin.glossVar) * 0.75, r5);
    return o;
}

// ---------------------------------------------------------------------------
// Ray / axis-aligned box. Used for the glass shell, the interior, and the caustic photons.
// Returns false on a miss. tN may be negative when the origin is already inside.
// ---------------------------------------------------------------------------
bool tpBox(float3 ro, float3 rd, float3 bmin, float3 bmax, out float tN, out float tF)
{
    float3 inv = 1.0 / (abs(rd) < 1e-8 ? (rd >= 0.0 ? 1e-8 : -1e-8) : rd);
    float3 t0 = (bmin - ro) * inv;
    float3 t1 = (bmax - ro) * inv;
    float3 lo = min(t0, t1);
    float3 hi = max(t0, t1);
    tN = max(max(lo.x, lo.y), lo.z);
    tF = min(min(hi.x, hi.y), hi.z);
    return tF > max(tN, 0.0);
}

// Outward normal of an axis-aligned box at a surface point, plus the face id of the INTERIOR
// (an inward-facing lining), which is what the atlas and the tile function want.
int tpInteriorFace(float3 p, float3 half3)
{
    float3 d = float3(abs(abs(p.x) - half3.x), abs(p.y + half3.y), abs(abs(p.z) - half3.z));
    if (d.y <= d.x && d.y <= d.z) return TP_FACE_FLOOR;
    if (d.x <= d.z) return (p.x < 0.0) ? TP_FACE_NX : TP_FACE_PX;
    return (p.z < 0.0) ? TP_FACE_NZ : TP_FACE_PZ;
}

float3 tpFaceNormal(int face)
{
    if (face == TP_FACE_FLOOR) return float3(0, 1, 0);
    if (face == TP_FACE_NX)    return float3(1, 0, 0);
    if (face == TP_FACE_PX)    return float3(-1, 0, 0);
    if (face == TP_FACE_NZ)    return float3(0, 0, 1);
    return float3(0, 0, -1);
}

// ---------------------------------------------------------------------------
// Fresnel, dielectric, unpolarized. Schlick is not good enough at the grazing angles this
// composition lives on — the whole read of a water surface is that it goes mirror at the far
// edge — so this is the real thing.
// ---------------------------------------------------------------------------
float tpFresnel(float cosI, float etaI, float etaT)
{
    cosI = saturate(abs(cosI));
    float sinT2 = (etaI / etaT) * (etaI / etaT) * (1.0 - cosI * cosI);
    if (sinT2 >= 1.0) return 1.0;                                // total internal reflection
    float cosT = sqrt(saturate(1.0 - sinT2));
    float rs = (etaI * cosI - etaT * cosT) / (etaI * cosI + etaT * cosT);
    float rp = (etaI * cosT - etaT * cosI) / (etaI * cosT + etaT * cosI);
    return saturate(0.5 * (rs * rs + rp * rp));
}

#endif // TESSERA_HLSLI
