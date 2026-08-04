// axon.hlsli — the axon_press data contract, lattice projection, palette and plate vocabulary.
//
// PLATE SPACE. The whole show is one flat AXONOMETRIC drawing. There is no perspective camera
// and no 3D renderer: the reference's identity is that parallel edges stay parallel, and a
// perspective fly-through destroys exactly that. The flight is instead a self-similar zoom of
// the drawing about a focus point.
//
// THE OCTAVE LOOP. One record set is drawn at AX_LEVELS scales s_j = R^(travel + j - L + 1).
// Advancing `travel` by 1 makes every layer take over the scale slot of the layer one step
// nearer, so the frame at travel = t and travel = t + P is the same frame. Anything that varies
// per octave is indexed by the INTEGER slot floor(log_R s) reduced mod AX_PERIOD, never by a
// float — a float-hashed octave strobes at the wrap, which is the classic infinite-zoom bug.
//
// Material detail is defined in FACE-LATTICE space, never in screen space, so it scales with
// its octave for free and the seam stays bit-exact no matter how deep the fractal detail goes.
//
// AX_Plan is the ONLY node that decides lattice placement, extents, material, colour, the
// focus, the fitted lattice unit, or travel. AX_Press reads records and owns nothing but pixels.
#ifndef AXON_PRESS_HLSLI
#define AXON_PRESS_HLSLI

// ---------------------------------------------------------------------------
// Record buffer. One buffer, `role` discriminates. 20 floats = 80 bytes.
// ---------------------------------------------------------------------------
#define AX_VOL_0     0u
#define AX_VOLS     32u
#define AX_PAN_0    32u
#define AX_PANS     20u
#define AX_WDG_0    52u
#define AX_WDGS     10u
#define AX_TRC_0    62u
#define AX_TRCS     10u
#define AX_HEADER   72u
#define AX_RECORDS  73u

#define ROLE_VOL     0.0
#define ROLE_PAN     1.0
#define ROLE_WDG     2.0
#define ROLE_TRC     3.0
#define ROLE_HEADER  4.0

#define F_SELECTED  1u
#define F_EDITED    2u
#define F_MATLOCK   4u   // material/colour set by hand: the per-cook refresh must leave it alone

struct AxRec
{
    // VOL/PAN/WDG: lattice base corner. TRC: lattice start point.
    float3 pos;
    // VOL: lattice extents (all >= 1). PAN/WDG: extents with exactly one component 0.
    // TRC: signed lattice delta to the far end.
    float3 ext;
    float  role;
    // VOL: AX_VK_*   PAN: AX_PK_*   WDG: corner 0-3   TRC: AX_TK_*
    float  kind;
    float  seed;
    // base material index into AX_M_*. Faces derive their own from this plus a per-face hash.
    float  mat;
    float  col;    // palette index into AX_PAL
    float  host;   // parent / host record index + 1, 0 = free
    float  rmin;   // DERIVED each cook: nearest plate radius from the focus, cell = 1 units
    float  rmax;   // DERIVED each cook: farthest
    float  phase;  // VOL/PAN: material phase   TRC: dash phase
    float  flags;
    float  active;
    float  pad0;
    float  pad1;
    float  pad2;
};

// volume forms — behavioural, not merely decorative
#define AX_VK_BLOCK  0   // solid box, three flat faces
#define AX_VK_FRAME  1   // edges only: the reference's open cube outlines. LETS LIGHT THROUGH.
#define AX_VK_OPEN   2   // open top, recessed inner floor
#define AX_VK_STEP   3   // a second smaller box set on top
#define AX_VK_SPLIT  4   // every face cut on a diagonal into two materials
#define AX_VKINDS    5

// panel forms
#define AX_PK_SHEET  0   // one flat quad
#define AX_PK_GRID   1   // subdivided into a tile grid, per-tile material (the checker register)
#define AX_PK_STRIP  2   // subdivided into bands along one axis (the newsprint columns)
#define AX_PKINDS    3

// trace forms
#define AX_TK_LINE   0
#define AX_TK_DASH   1
#define AX_TK_ELBOW  2   // axis-following route: x leg, then y leg, then z leg
#define AX_TK_TICK   3   // line with cross ticks
#define AX_TKINDS    4

// plate materials. Every one is procedural and evaluated in FACE-LATTICE space.
#define AX_M_NEWS    0   // grey column text
#define AX_M_HEAD    1   // a headline band over column text
#define AX_M_HOUND   2   // houndstooth
#define AX_M_CHECK   3   // checkerboard
#define AX_M_STRIPE  4   // fine horizontal rules
#define AX_M_HALF    5   // halftone dot field
#define AX_M_SOLID   6   // flat colour
#define AX_M_BARS    7   // heavy bar block
#define AX_MATS      8

// ---------------------------------------------------------------------------
// Palette, transcribed off the reference. Not an exploration axis — one chord, chosen once.
// ---------------------------------------------------------------------------
#define AX_COLS 12
static const float3 AX_PAL[AX_COLS] = {
    float3(0.930, 0.098, 0.545),   //  0 hot magenta
    float3(0.204, 0.718, 0.855),   //  1 cyan
    float3(0.902, 0.420, 0.098),   //  2 orange
    float3(0.329, 0.157, 0.471),   //  3 violet
    float3(0.137, 0.204, 0.478),   //  4 deep blue
    float3(0.157, 0.600, 0.420),   //  5 teal
    float3(0.933, 0.620, 0.722),   //  6 pale pink
    float3(0.055, 0.055, 0.075),   //  7 near black
    float3(0.545, 0.537, 0.518),   //  8 warm grey
    float3(0.816, 0.796, 0.749),   //  9 newsprint
    float3(0.949, 0.949, 0.933),   // 10 white
    float3(0.435, 0.898, 0.298)    // 11 signal green
};
float3 axPal(int i) { return AX_PAL[(int)clamp((float)i, 0.0, (float)(AX_COLS - 1))]; }

// the ground the drawing sits on, and what the deepest octave fades into
#define AX_FIELD float3(0.035, 0.036, 0.046)

// trace inks — the bright hairlines. Deliberately a separate, hotter set.
#define AX_TRACE_INKS 4
static const float3 AX_INK[AX_TRACE_INKS] = {
    float3(0.949, 0.145, 0.180),   // vermilion
    float3(0.176, 0.831, 0.898),   // cyan
    float3(0.478, 0.949, 0.278),   // green
    float3(0.965, 0.353, 0.639)    // pink
};

// ---------------------------------------------------------------------------
// Hashes. ax_ prefixed so they can never collide with an injected feature signature.
// ---------------------------------------------------------------------------
float ax_rnd(float s, float k)
{
    return frac(sin(s * 12.9898 + k * 78.233) * 43758.5453);
}
float ax_h2(float2 p)
{
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}
float ax_h3(float3 p)
{
    return frac(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453);
}

// ---------------------------------------------------------------------------
// The lattice. Integer coordinates are what makes volumes INTERLOCK: two boxes on the same
// integer grid share face planes automatically, which is the relationship the reference is
// actually made of. A randomizer may move a record freely along the lattice without ever
// producing the detached debris that free coordinates give.
//
// Screen basis: +X goes right-and-down, +Y left-and-down, +Z straight up. Both ground axes
// come TOWARD the viewer, so the classic isometric painter key d = x + y + z orders any two
// axis-aligned boxes correctly. Projections whose +X carries no screen depth (Cabinet) get a
// small positive weight instead, purely to break ties consistently.
// ---------------------------------------------------------------------------
#define AX_LAT_ISO      0
#define AX_LAT_DIMETRIC 1
#define AX_LAT_CABINET  2
#define AX_LAT_STEEP    3

void axBasis(int lat, out float2 A, out float2 B, out float2 C, out float3 D)
{
    if (lat == AX_LAT_DIMETRIC)      { A = float2( 0.940, -0.342); B = float2(-0.750, -0.620); D = float3(1.0, 1.0, 1.0); }
    else if (lat == AX_LAT_CABINET)  { A = float2( 1.000,  0.000); B = float2(-0.470, -0.470); D = float3(0.15, 1.0, 1.0); }
    else if (lat == AX_LAT_STEEP)    { A = float2( 0.800, -0.680); B = float2(-0.800, -0.680); D = float3(1.0, 1.0, 1.0); }
    else                             { A = float2( 0.866, -0.500); B = float2(-0.866, -0.500); D = float3(1.0, 1.0, 1.0); }
    C = float2(0.0, 1.0);
}

float2 axProj(float3 p, float2 A, float2 B, float2 C)
{
    return p.x * A + p.y * B + p.z * C;
}

// Plate point -> lattice ground coordinates (z = 0). The focus is CONSTRAINED to the ground
// plane, which is what makes dragging it a well-posed 2x2 solve instead of an underdetermined
// 2-into-3. It is also where a draughtsman would put it.
float2 axUnproj(float2 q, float2 A, float2 B)
{
    float det = A.x * B.y - A.y * B.x;
    if (abs(det) < 1e-8) return float2(0.0, 0.0);
    return float2(q.x * B.y - q.y * B.x, A.x * q.y - A.y * q.x) / det;
}

// Solve q = O + u*U + v*V. Degenerate (zero-area) faces return false, which is exactly what
// collapses a box into a PANEL when one extent is zero — one primitive, four roles.
bool axPara(float2 q, float2 O, float2 U, float2 V, out float2 uv)
{
    uv = float2(0.0, 0.0);
    float det = U.x * V.y - U.y * V.x;
    if (abs(det) < 1e-7) return false;
    float2 d = q - O;
    uv = float2(d.x * V.y - d.y * V.x, U.x * d.y - U.y * d.x) / det;
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

#define AX_FACE_TOP   0
#define AX_FACE_RIGHT 1
#define AX_FACE_LEFT  2

// Which of the three visible faces a plate point lands on, its face-lattice coordinates, and
// the painter depth of the lattice point actually hit. For a convex box in axonometric the
// three visible faces tile the silhouette exactly, so at most one can hit.
bool axBoxHit(float3 b, float3 e, float2 q, float2 A, float2 B, float2 C, float3 D,
              out int face, out float2 fl, out float depth)
{
    face = -1; fl = float2(0.0, 0.0); depth = -1e9;
    float2 uv;

    // TOP: z = b.z + e.z
    if (axPara(q, axProj(b + float3(0.0, 0.0, e.z), A, B, C), A * e.x, B * e.y, uv))
    {
        face = AX_FACE_TOP;
        fl = float2(uv.x * e.x, uv.y * e.y);
        depth = dot(b + float3(uv.x * e.x, uv.y * e.y, e.z), D);
        return true;
    }
    // RIGHT: x = b.x + e.x
    if (axPara(q, axProj(b + float3(e.x, 0.0, 0.0), A, B, C), B * e.y, C * e.z, uv))
    {
        face = AX_FACE_RIGHT;
        fl = float2(uv.x * e.y, uv.y * e.z);
        depth = dot(b + float3(e.x, uv.x * e.y, uv.y * e.z), D);
        return true;
    }
    // LEFT: y = b.y + e.y
    if (axPara(q, axProj(b + float3(0.0, e.y, 0.0), A, B, C), A * e.x, C * e.z, uv))
    {
        face = AX_FACE_LEFT;
        fl = float2(uv.x * e.x, uv.y * e.z);
        depth = dot(b + float3(uv.x * e.x, e.y, uv.y * e.z), D);
        return true;
    }
    return false;
}

// Bounding circle in plate space, cell = 1. Used as the early-out before the three-face solve;
// without it the renderer runs every record against every pixel at every octave.
void axBound(float3 b, float3 e, float2 A, float2 B, float2 C, out float2 ctr, out float rad)
{
    float3 e0 = min(e, 0.0), e1 = max(e, 0.0);         // signed extents (traces run negative)
    float2 lo = float2(1e9, 1e9), hi = float2(-1e9, -1e9);
    for (int i = 0; i < 8; i++)
    {
        float3 p = b + float3(((i & 1) != 0) ? e1.x : e0.x,
                              ((i & 2) != 0) ? e1.y : e0.y,
                              ((i & 4) != 0) ? e1.z : e0.z);
        float2 s = axProj(p, A, B, C);
        lo = min(lo, s); hi = max(hi, s);
    }
    ctr = (lo + hi) * 0.5;
    rad = length(hi - lo) * 0.5 + 1e-4;
}

float axSegD(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-9));
    return length(p - a - ab * t);
}

// Nearest and farthest plate radius of a record from the focus, cell = 1 units. This is the
// number the octave ladder is built on: a record whose (rmax/rmin) exceeds the octave ratio
// will visibly interpenetrate its own copy one octave up, and that has to be readable in the
// diagram rather than discovered as mush in the render.
void axRadial(AxRec r, float2 f, float2 A, float2 B, float2 C, out float rmin, out float rmax)
{
    float3 b = r.pos, e = r.ext;
    if (r.role == ROLE_TRC)
    {
        float2 p0 = axProj(b, A, B, C);
        float2 p1 = axProj(b + e, A, B, C);
        rmin = axSegD(f, p0, p1);
        rmax = max(length(p0 - f), length(p1 - f));
        return;
    }
    rmin = 1e9; rmax = 0.0;
    float2 cn[8];
    for (int i = 0; i < 8; i++)
    {
        float3 p = b + float3(((i & 1) != 0) ? e.x : 0.0,
                              ((i & 2) != 0) ? e.y : 0.0,
                              ((i & 4) != 0) ? e.z : 0.0);
        cn[i] = axProj(p, A, B, C);
        rmax = max(rmax, length(cn[i] - f));
    }
    // 12 lattice edges: every pair differing in exactly one bit
    for (int j = 0; j < 8; j++)
    {
        for (int k = 0; k < 3; k++)
        {
            int m = 1 << k;
            if ((j & m) != 0) continue;
            rmin = min(rmin, axSegD(f, cn[j], cn[j | m]));
        }
    }
}

// ---------------------------------------------------------------------------
// The octave loop. AX_APER_L is the clear radius the arrangement is fitted to, in cell = 1
// units; the plan publishes the cell size that puts it exactly at the requested plate aperture,
// which is a single uniform similarity and therefore changes no proportion anywhere.
// ---------------------------------------------------------------------------
#define AX_APER_L  4.0

// The integer octave slot of a scale, and its reduction into the loop period. Everything that
// varies per octave routes through this and only this.
int axSlotMod(int slot, int period)
{
    int p = max(period, 1);
    return ((slot % p) + p) % p;
}

// The four live family tallies packed into one header float, so the header can also carry the
// projection, the octave ratio and the loop period downstream. Well inside float precision.
float axPackCounts(uint v, uint p, uint w, uint t)
{
    return (float)v + (float)p * 40.0 + (float)w * 960.0 + (float)t * 11520.0;
}
void axUnpackCounts(float k, out uint v, out uint p, out uint w, out uint t)
{
    v = (uint)fmod(k, 40.0);
    p = (uint)fmod(floor(k / 40.0), 24.0);
    w = (uint)fmod(floor(k / 960.0), 12.0);
    t = (uint)floor(k / 11520.0);
}

// ---------------------------------------------------------------------------
// Editor geometry. Shared verbatim by plan.hlsl and canvas.hlsl so a handle is always
// grabbable exactly where it is drawn. Normalized uv, origin top-left, +y DOWN.
//
// The diagram is THE PLATE over THE OCTAVE LADDER, sharing the radius axis: the plate carries
// the axonometric arrangement with octave rings drawn round the focus, and the ladder unrolls
// the same radii onto a log axis where the wrap seam and the coverage gaps live. One view
// cannot show both — the plate cannot show periodicity and the ladder cannot show composition.
// ---------------------------------------------------------------------------
#define AX_PLATE_CX  0.3075
#define AX_PLATE_CY  0.5000
#define AX_PLATE_HY  0.4350
#define AX_ASPECT    0.5625          // 648 / 1152, canvas is authored at that shape

#define AX_LAD_X0    0.6300
#define AX_LAD_X1    0.9750
#define AX_LAD_Y0    0.0800
#define AX_LAD_Y1    0.5300
#define AX_COV_Y0    0.5750
#define AX_COV_Y1    0.7450

float axPlateHX() { return AX_PLATE_HY * AX_ASPECT; }

// The plate view's half-extent, derived from the same two parameters the ladder is drawn from
// so the two strips can never disagree about how far out the arrangement reaches.
float axViewHalf(float span, float ratio)
{
    // 1.40 leaves margin for the largest records, whose extents reach well past the radius band
    // their centres were drawn in. At a tighter figure the plate view clips its own subject.
    return AX_APER_L * pow(max(ratio, 1.05), max(span, 0.2)) * 1.40;
}

// plate-space offset from the focus (cell = 1 units) -> canvas uv
float2 axPlateToUv(float2 v, float viewHalf)
{
    float2 n = v / max(viewHalf, 1e-4);
    return float2(AX_PLATE_CX + n.x * axPlateHX(), AX_PLATE_CY - n.y * AX_PLATE_HY);
}
float2 axUvToPlate(float2 uv, float viewHalf)
{
    return float2((uv.x - AX_PLATE_CX) / axPlateHX(), -(uv.y - AX_PLATE_CY) / AX_PLATE_HY) * viewHalf;
}

// log-radius -> ladder x. rho = log_R(r / AX_APER_L), so 0 is the aperture and each unit is
// one octave.
float axRhoToX(float rho, float spanView)
{
    return AX_LAD_X0 + saturate(rho / max(spanView, 0.2)) * (AX_LAD_X1 - AX_LAD_X0);
}
float axXToRho(float x, float spanView)
{
    return (x - AX_LAD_X0) / max(AX_LAD_X1 - AX_LAD_X0, 1e-4) * max(spanView, 0.2);
}
float axRho(float r, float ratio)
{
    return log(max(r, 1e-4) / AX_APER_L) / log(max(ratio, 1.05));
}

// Which region a canvas point belongs to. 1 = plate, 2 = ladder, 3 = coverage, 0 = nowhere.
int axRegionAt(float2 uv)
{
    if (uv.x > AX_LAD_X0 - 0.02 && uv.x < AX_LAD_X1 + 0.02)
    {
        if (uv.y > AX_LAD_Y0 - 0.02 && uv.y < AX_LAD_Y1 + 0.02) return 2;
        if (uv.y > AX_COV_Y0 - 0.02 && uv.y < AX_COV_Y1 + 0.02) return 3;
        return 0;
    }
    if (abs(uv.x - AX_PLATE_CX) < axPlateHX() + 0.03 &&
        abs(uv.y - AX_PLATE_CY) < AX_PLATE_HY + 0.03) return 1;
    return 0;
}

#endif // AXON_PRESS_HLSLI
