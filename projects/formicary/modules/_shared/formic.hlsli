// formic.hlsli — the shared contract for formicary.
//
// Everything here is a DEFINITION every node in the show must agree on: the record layouts,
// the coordinate systems, the route curve, and the obstacle field. Nothing in this file
// DECIDES anything. FM_Plan decides placement, FM_Colony decides where the ants are; this
// file only says how those decisions are spelled so that four nodes cannot spell them
// differently.
//
// ---------------------------------------------------------------------------
// ARENA SPACE — world units are MILLIMETRES, because the subject has a real size.
//
//   x  right
//   y  up, ground plane at y = 0
//   z  away from the viewer (down the page in plan)
//
// A fire ant worker is about 4 mm nose to gaster tip and spans about 9 mm across its legs.
// Keeping the world in real millimetres means the camera's focal distance, the depth of
// field, the pheromone diffusion rate and the stride length are all quantities that can be
// checked against a photograph instead of tuned blind.
//
// FOOTPRINT SPACE (normalized, -1..1 across the arena half-extents) is what the PLACEMENT of
// a nest / cache / obstacle is stored in. Radii and extents stay in millimetres. The split is
// deliberate and it is the same lesson koi_tank paid for: resizing the arena must not throw a
// hand-placed record outside it, but a 4 mm pebble must stay a 4 mm pebble.
// ---------------------------------------------------------------------------
#ifndef FORMIC_HLSLI
#define FORMIC_HLSLI

// ---------------------------------------------------------------------------
// THE PLAN RECORD. 20 floats / 80 bytes. One buffer, role-discriminated — the arena, the
// nest, the food, the obstacles and the trail network all live in it, because they are one
// arrangement and splitting them into parallel buffers is how they drift apart.
// ---------------------------------------------------------------------------
struct FmRec
{
    float3 pos;      // footprint (fx, 0, fz) for placed records | light: direction
    float3 dims;     // arena: (halfX, 0, halfZ) mm | nest/cache: (radius,0,0) | obst: (halfL, height, halfW)
                     // edge: (ctrlX, 0, ctrlZ) mm — the route's mid control-point offset
    float  role;
    float  kind;     // obst: 0 pebble / 1 twig / 2 leaf   | cache: food kind
    float3 tint;
    float  seed;
    float  p0;       // cache: payload | obst: yaw | edge: FROM slot | light: key | arena: grain
    float  p1;       // cache: scent   | obst: sink | edge: TO slot   | light: sky | arena: tone
    float  p2;       // cache: kind mix               | edge: recruitment 0..1     | light: shadow soften
    float  p3;       //                                 edge: route length (derived, mm)
    float  flags;
    float  active;
    float  pad0;
    float  pad1;
};

// Fixed slots. Every node indexes the same way; nothing searches the buffer by role.
//
// The station range is APPENDED rather than inserted. Every index below it keeps the value it
// has always had, so a plan buffer persisted by an older build still reads correctly and only
// the new tail arrives uninitialised — which the generator overwrites unconditionally anyway.
#define FM_HEADER   0u
#define FM_ARENA    1u
#define FM_LIGHT    2u
#define FM_NEST     3u
#define FM_CACHE_0  4u
#define FM_CACHES   6u
#define FM_OBST_0  10u
#define FM_OBSTS   12u
#define FM_EDGE_0  22u
#define FM_EDGES   10u
#define FM_PAL_0   32u
#define FM_PALS     4u
#define FM_STA_0   36u
#define FM_STAS    16u
#define FM_COUNT   52u

#define ROLE_HEADER 0.0
#define ROLE_ARENA  1.0
#define ROLE_LIGHT  2.0
#define ROLE_NEST   3.0
#define ROLE_CACHE  4.0
#define ROLE_OBST   5.0
#define ROLE_EDGE   6.0
#define ROLE_PAL    7.0
#define ROLE_STA    8.0

// ---------------------------------------------------------------------------
// STATIONS — the placed points that do something to the colony.
//
// One role with a KIND discriminator rather than four roles, because they are one thing to the
// user: a point you put down, drag, retune and switch between behaviours. Four parallel ranges
// would need four sets of pick code, four sets of drag code and four captions, and the first
// thing anyone would ask for is to turn an attractor into a repeller without moving it.
//
// A station's fields, on top of the common pos / dims.x = radius / tint / active:
//
//   p0   STRENGTH.  emit: ants per second      attract/repel: steering gain
//                   sink: ants per second swallowed
//   p1   MODE within the kind. See STA_M_* below.
//   p2   BUDGET.    emit: how many ants this station may have out at once (0 = unlimited)
//                   sink: unused
//   p3   RATE.      emit: burst size          attract/repel: pulse frequency, Hz
//   pad0 TRIGGER.   monotonic counter. FM_Plan bumps it on a fire gesture; the colony compares
//                   it against the value it last saw and acts on the DIFFERENCE, so a trigger
//                   cannot be missed by a dropped frame or double-counted by a slow one.
//   dims.z SPREAD.  emit: release cone half-angle, radians
// ---------------------------------------------------------------------------
#define STA_EMIT    0.0
#define STA_ATTRACT 1.0
#define STA_REPEL   2.0
#define STA_SINK    3.0
#define STA_KINDS   4u

// Emitter modes.
#define STA_M_DRIP  0.0   // a steady rate, continuously
#define STA_M_BURST 1.0   // nothing until fired, then p3 ants at once
#define STA_M_RING  2.0   // steady rate, released around the radius instead of at the centre
// Attractor / repeller modes.
#define STA_M_STEADY 0.0
#define STA_M_PULSE  1.0  // strength beats at p3 Hz — a column that surges rather than flows
// Sink modes.
#define STA_M_RECYCLE 0.0 // the ant goes dormant and an emitter may release it again
#define STA_M_CONSUME 1.0 // the ant goes dormant and stays that way

// One definition of a station's reach, its instantaneous strength and its falloff, shared by
// the colony that steers on it and the plan that draws it. If the drawing derived its own the
// ring would show a radius the ants were not obeying, and every tuning session after that would
// be spent trying to fix steering that was never wrong.
float fmStaRadius(FmRec s) { return max(s.dims.x, 0.5); }

float fmStaFalloff(float d, float r)
{
    float q = saturate(d / max(r, 1e-3));
    float k = 1.0 - q;
    return k * k;               // smooth at the rim, finite support, no tail to fog the arena
}

// A pulsing station BEATS rather than fades: the trough is zero, so a column visibly surges and
// releases instead of merely breathing. Phase is offset by the record's seed, so two pulsing
// stations placed together do not lock into one throb.
float fmStaStrength(FmRec s, float t)
{
    int kind = (int)(s.kind + 0.5);
    int mode = (int)(s.p1 + 0.5);
    float g = s.p0;
    if (mode == 1 && (kind == 1 || kind == 2))
    {
        float hz = clamp(s.p3, 0.02, 12.0);
        float ph = t * hz + s.seed * 0.017;
        g *= saturate(0.5 - 0.5 * cos(ph * 6.2831853));
    }
    return g;
}

#define OBST_PEBBLE 0.0
#define OBST_TWIG   1.0
#define OBST_LEAF   2.0

#define F_EDITED   1u
#define F_SELECTED 2u
// The failure mode. An edge whose route passes through an obstacle, or leaves the arena, is
// a route the colony cannot walk. FM_Plan sets this and the plan strip draws it in alarm red.
#define F_BLOCKED  4u

// Palette slots. Fire ant chitin is not one colour: the gaster is darker and far glossier
// than the mesosoma, and the legs and antennae are paler and translucent at this scale.
#define FM_PAL_GASTER 0u
#define FM_PAL_THORAX 1u
#define FM_PAL_LIMB   2u
#define FM_PAL_GROUND 3u

// ---------------------------------------------------------------------------
// THE ANT RECORD. 20 floats / 80 bytes. FM_Colony owns it; FM_Render and FM_Scope read it
// and neither re-decides a position, a heading or a gait phase.
// ---------------------------------------------------------------------------
struct FmAnt
{
    float3 pos;      // world mm. y is the MESOSOMA height above ground, not the foot plane.
    float3 dir;      // heading, unit, horizontal
    float  speed;    // mm/s, the measured value not the target
    float  gait;     // gait cycle phase, 0..1, wraps
    float3 tint;     // this individual's chitin, derived from the palette with small variance
    float  size;     // body length, mm
    float  task;     // 0 outbound / 1 loading at a cache / 2 laden return / 3 unloading at nest
    float  load;     // 0..1 carried
    float  seed;
    float  turn;     // measured signed yaw rate, rad/s. This is what the predicted path bends by.
    float  edge;     // trail edge slot + 1, 0 = off-trail
    float  active;
    float  antenna;  // antennal sweep phase
    float  contact;  // antennation strength with the nearest neighbour, 0..1

    // --- added for the station system. The record grew from 80 to 96 bytes; every schema that
    // names it — FM_Colony's state_buffers and data_outputs, FM_Render's and FM_Scope's
    // data_inputs — carries these four or the whole buffer is read at the wrong stride, which
    // presents as ants scattered across the arena in a regular diagonal rather than as a
    // mismatched schema.
    float  home;     // station slot + 1 that released this ant. 0 = it came from the nest.
    float  age;      // seconds since release. Drives emergence and nothing else.
    float  fade;     // 0..1 presence. An ant does not pop: it emerges from an emitter and
                     // shrinks into a sink, and the renderer scales the body by this.
    float  pad2;
};

// A dormant ant is one no emitter has released yet, or one a sink has swallowed. It is not
// drawn, not measured, and not smelled — it is a free slot in the pool. Task 4 rather than a
// separate flag so the one switch in walk.hlsl that already dispatches on task covers it.
#define FM_TASK_OUT     0.0
#define FM_TASK_LOAD    1.0
#define FM_TASK_LADEN   2.0
#define FM_TASK_UNLOAD  3.0
#define FM_TASK_DORMANT 4.0

// ---------------------------------------------------------------------------
// THE FOOT RECORD. 12 floats / 48 bytes. Six per ant, laid out ant-major:
//   foot index = ant * FM_LEGS + leg
//
// A planted foot is stored in WORLD space and does not move while it is planted. That is the
// whole point: a leg drawn from a body-relative offset slides across the ground with the body
// and no amount of shading fixes it, because the error is that the foot is not a foot.
// ---------------------------------------------------------------------------
struct FmFoot
{
    float3 pos;      // world mm, tarsus tip
    float  stance;   // 1 = planted and bearing, 0 = swinging. Smooth, not a boolean.
    float3 home;     // body-local neutral stance offset, mm (x lateral, y 0, z fore/aft)
    float  slip;     // MEASURED mm the tarsus was FORCED to move while it was supposed to be planted
    float3 lift;     // world position at the moment this leg left the ground; the swing's start
    float  phase;    // this leg's own cycle phase, 0..1
};

// Which tripod a leg belongs to. Legs 0,1,2 are left front/middle/rear and 3,4,5 are right
// front/middle/rear, so the alternating tripod is {left front, left rear, right middle} against
// {left middle, right front, right rear} — which this expression produces exactly.
uint fmLegGroup(uint leg) { return ((leg % 3u) + (leg / 3u)) % 2u; }

// ---------------------------------------------------------------------------
// PUBLIC EXAMPLE POPULATION. The authored ceiling is 128 ants.
//
// What that costs, and why each cost is paid where it is:
//
//   walk / gait   were one thread group of 64 with an exact groupshared neighbourhood. At 1024
//                 they are 16 groups, and groupshared cannot span groups — so the neighbourhood
//                 moved to the bucket grid below. It is one cook stale, which for separation
//                 between animals moving at 22 mm/s is under a tenth of a body width.
//
//   pher          deposits by GATHER — every texel asked every ant. At 64 ants that was 3.9 M
//                 tests and free. At 1024 it would be 63 M, which is not. The grid turns it
//                 back into a local question.
//
//   render        3552 vertices an ant is 3.6 M vertices at full population. That is the real
//                 bill, and it is what FM_Render's detail ladder exists to trade.
// ---------------------------------------------------------------------------
#define FM_MAX_ANTS 128u
#define FM_LEGS      6u
#define FM_MAX_FEET (FM_MAX_ANTS * FM_LEGS)

// Thread groups. One group per 64 ants; every dispatch that walks the population uses these two
// together so a change here cannot be applied to the gait and forgotten on the walk.
#define FM_ANT_TGX   64u
#define FM_ANT_GROUPS (FM_MAX_ANTS / FM_ANT_TGX)

// ---------------------------------------------------------------------------
// THE BUCKET GRID. A uniform grid over the arena holding the ants that were in each cell as of
// the previous cook, so that "who is near me" and "who is near this texel" stop being questions
// about the whole population.
//
// Built by a GATHER — one thread per cell, looping the population and keeping what belongs to
// it — rather than by a scatter with atomics. It costs more arithmetic and buys the thing that
// matters: no atomics, no clear pass to be scheduled after the accumulate it precedes, and a
// bit-identical result every run.
//
// Capacity is deliberately generous. Ants on a shared trail bunch, and a full 12 mm cell of
// 1.5 mm ants holds far more than the 1.4 the average suggests; an overflowing cell silently
// drops neighbours, which reads as ants walking through each other in exactly the crowd where
// you are looking hardest.
// ---------------------------------------------------------------------------
#define FM_GRID_X   28u
#define FM_GRID_Z   20u
#define FM_GRID_N   (FM_GRID_X * FM_GRID_Z)
#define FM_CELL_CAP 48u

// One ant as the grid stores it: enough for separation AND for the pheromone deposit, so the
// two consumers share one build instead of each walking the population for itself.
struct FmCellAnt
{
    float2 pos;      // world mm on the ground plane
    float  idx;      // WHICH ant. Without it an ant finds ITSELF in the grid — one cook back,
                     // so a third of a millimetre away — and shoves itself sideways at nearly
                     // full separation weight, every frame, forever.
    float  task;
    float  load;
    float  size;
    float  fade;
};

struct FmCell
{
    float count;
    float pad0, pad1, pad2;
    FmCellAnt a[FM_CELL_CAP];
};

// Which cell a world point falls in. Clamped rather than rejected: an ant pushed a hair outside
// the arena by a steering impulse still has neighbours and still lays scent.
int2 fmGridCell(float2 w, float2 ahalf)
{
    float2 t = saturate((w + ahalf) / max(ahalf * 2.0, 1e-3));
    return int2(min((int)(t.x * FM_GRID_X), (int)FM_GRID_X - 1),
                min((int)(t.y * FM_GRID_Z), (int)FM_GRID_Z - 1));
}
uint fmGridIndex(int2 c) { return (uint)c.y * FM_GRID_X + (uint)c.x; }

// The largest radius a 3x3 cell query is guaranteed to cover. Anything asking for more than this
// must widen its loop or accept a clipped answer, and both consumers clamp to it rather than
// quietly reading a neighbourhood smaller than the one they think they asked for.
float fmGridCellSpan(float2 ahalf) { return min(ahalf.x * 2.0 / FM_GRID_X, ahalf.y * 2.0 / FM_GRID_Z); }

// ---------------------------------------------------------------------------
// Hashing. Cheap, stable across nodes, and deliberately identical everywhere so that a seed
// means the same arrangement in the plan strip as it does in the renderer.
// ---------------------------------------------------------------------------
uint fmHashU(uint x)
{
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

float fmRnd(float a, float b)
{
    return (float)(fmHashU(asuint(a * 127.1 + b * 311.7 + 13.0)) & 0x00ffffffu) / 16777216.0;
}

float fmRnd2(uint i, float s)
{
    return (float)(fmHashU(i * 2654435761u ^ asuint(s + 1.7)) & 0x00ffffffu) / 16777216.0;
}

float2 fmRnd22(uint i, float s)
{
    return float2(fmRnd2(i * 3u + 1u, s), fmRnd2(i * 3u + 2u, s));
}

// Signed, centred on zero.
float fmSRnd(uint i, float s) { return fmRnd2(i, s) * 2.0 - 1.0; }

// ---------------------------------------------------------------------------
// Arena conversions.
// ---------------------------------------------------------------------------
float2 fmArenaHalf(FmRec arena) { return float2(max(arena.dims.x, 1.0), max(arena.dims.z, 1.0)); }
float2 fmFootToWorld(float2 f, FmRec arena) { return f * fmArenaHalf(arena); }
float2 fmWorldToFoot(float2 w, FmRec arena) { return w / fmArenaHalf(arena); }

// A placed record's world position on the ground plane.
float2 fmRecWorld(FmRec r, FmRec arena) { return fmFootToWorld(float2(r.pos.x, r.pos.z), arena); }

// ---------------------------------------------------------------------------
// THE SHARED TOP-DOWN PROJECTION.
//
// Three nodes draw the arena from above — the plan's diagram strip, the colony's live view and
// the stage's plan mode — and they MUST agree, because the whole point of looking at two of them
// is to compare them. They did not: the plan was corrected to draw world +x to the left and the
// colony kept drawing it to the right, so the same colony appeared as two mirror images with
// nothing to say which was which.
//
// The page orientation therefore travels in the ARENA RECORD (`p2`), written by the plan
// authority, rather than as a parameter each node is trusted to copy. Both options are rigid
// half-turns of the measured overhead view; see FM_Plan/layout.hlsli for the derivation and the
// measurement it came from.
// ---------------------------------------------------------------------------
float2 fmArenaAxis(FmRec arena)
{
    return (((int)(arena.p2 + 0.5)) == 0) ? float2(-1.0, 1.0) : float2(1.0, -1.0);
}

struct FmTop
{
    float2 c;      // pixel centre of the arena
    float  scale;  // pixels per millimetre
    float2 axis;   // page direction of world +x and +z
};

// Fit the arena into a pixel rectangle, preserving aspect. `inset` leaves room for whatever the
// caller draws around the edge; 1.0 is edge to edge.
FmTop fmTopFit(float2 lo, float2 hi, FmRec arena, float inset)
{
    FmTop t;
    float2 half = fmArenaHalf(arena);
    float2 span = max(hi - lo, 1.0);
    t.scale = min(span.x / (2.0 * half.x), span.y / (2.0 * half.y)) * inset;
    t.c = (lo + hi) * 0.5;
    t.axis = fmArenaAxis(arena);
    return t;
}

float2 fmTopToPx(FmTop t, float2 w)  { return t.c + w * t.axis * t.scale; }
float2 fmPxToTop(FmTop t, float2 px) { return (px - t.c) / t.scale * t.axis; }

// A world box maps to a pixel box whose corners SWAP when a page axis is negative.
void fmTopBoxPx(FmTop t, float2 wLo, float2 wHi, out float2 pLo, out float2 pHi)
{
    float2 a = fmTopToPx(t, wLo), b = fmTopToPx(t, wHi);
    pLo = min(a, b); pHi = max(a, b);
}

// ---------------------------------------------------------------------------
// THE ROUTE. A quadratic Bezier from node A to node B through one stored control offset.
//
// One definition, used by four different questions: the plan strip draws it, the blocked test
// walks it, the colony follows it, and the scope reports how far along it an ant is. If any of
// those computed the curve for itself they would disagree in exactly the places that matter —
// the bends, which is where the obstacles are.
// ---------------------------------------------------------------------------
float2 fmRoutePoint(float2 a, float2 b, float2 ctrl, float t)
{
    float2 mid = (a + b) * 0.5 + ctrl;
    float u = 1.0 - t;
    return u * u * a + 2.0 * u * t * mid + t * t * b;
}

// Analytic tangent. Never differenced from two samples: near t=0 and t=1 the difference is
// dominated by whichever step size the caller happened to pick.
float2 fmRouteTangent(float2 a, float2 b, float2 ctrl, float t)
{
    float2 mid = (a + b) * 0.5 + ctrl;
    float2 d = 2.0 * ((1.0 - t) * (mid - a) + t * (b - mid));
    float l = length(d);
    return (l > 1e-5) ? d / l : normalize(b - a + float2(1e-4, 0.0));
}

// ---------------------------------------------------------------------------
// THE OBSTACLE FIELD. Signed distance in world millimetres on the ground plane, negative
// inside. Shared by the plan (blocked test and drawing), the field (mask bake), the colony
// (avoidance steering) and the renderer (the solid itself), so an ant can never walk through
// something the picture shows as solid.
// ---------------------------------------------------------------------------
float fmObstDist(float2 w, FmRec o, FmRec arena)
{
    float2 c = fmRecWorld(o, arena);
    float2 d = w - c;
    float ca = cos(o.p0), sa = sin(o.p0);
    float2 q = float2(d.x * ca + d.y * sa, -d.x * sa + d.y * ca);

    float hl = max(o.dims.x, 0.05);   // half length along local x
    float hw = max(o.dims.z, 0.05);   // half width along local y

    int k = (int)(o.kind + 0.5);

    if (k == 1)
    {
        // Twig — a capsule. Long, thin, and the only obstacle that can span a whole route.
        float h = max(hl - hw, 0.0);
        q.x -= clamp(q.x, -h, h);
        return length(q) - hw;
    }

    if (k == 2)
    {
        // Leaf — an ellipse tapered to a point at both ends. The taper is what makes a leaf
        // read as a leaf and not a second pebble, and it matters for steering too: an ant
        // meeting a leaf near its tip should slide off rather than stop.
        float t = clamp(q.x / hl, -1.0, 1.0);
        float wprof = hw * pow(max(1.0 - t * t, 0.0), 0.62);
        float ox = abs(q.x) - hl;
        float oy = abs(q.y) - wprof;
        return length(max(float2(ox, oy), 0.0)) + min(max(ox, oy), 0.0);
    }

    // Pebble — an ellipse. Scaled-circle estimate, which under-reports distance far away and
    // is exact at the boundary; the boundary is the only place any consumer cares.
    float2 e = float2(hl, hw);
    float2 pe = q / e;
    return (length(pe) - 1.0) * min(e.x, e.y);
}

// Nearest obstacle over the whole set, plus the outward gradient. A MACRO rather than a
// function because cs_5_0 cannot take a StructuredBuffer as a parameter, and the alternative —
// letting each consumer write its own loop — is exactly how the mask and the steering end up
// disagreeing about which obstacle is nearest.
//
//   BUF    a StructuredBuffer<FmRec> holding the plan
//   ARENA  the arena record
//   W      float2 world position on the ground
//   O_D    float  out: signed distance, negative inside
//   O_N    float2 out: unit outward normal at the nearest surface
#define FM_OBST_QUERY(BUF, ARENA, W, O_D, O_N)                                                \
{                                                                                             \
    O_D = 1e9; O_N = float2(0.0, 1.0);                                                        \
    for (uint _oi = 0u; _oi < FM_OBSTS; _oi++)                                                \
    {                                                                                         \
        FmRec _o = BUF[FM_OBST_0 + _oi];                                                       \
        if (_o.active < 0.5) continue;                                                        \
        float _d = fmObstDist(W, _o, ARENA);                                                   \
        if (_d < O_D)                                                                          \
        {                                                                                      \
            O_D = _d;                                                                          \
            float _e = 0.25;                                                                   \
            float2 _g = float2(fmObstDist(W + float2(_e, 0), _o, ARENA)                        \
                             - fmObstDist(W - float2(_e, 0), _o, ARENA),                       \
                               fmObstDist(W + float2(0, _e), _o, ARENA)                        \
                             - fmObstDist(W - float2(0, _e), _o, ARENA));                      \
            float _gl = length(_g);                                                            \
            O_N = (_gl > 1e-5) ? _g / _gl : float2(0.0, 1.0);                                  \
        }                                                                                      \
    }                                                                                          \
}

// ---------------------------------------------------------------------------
// The pheromone field's own space. FM_Field rasterizes the arena footprint into a square
// texture; every consumer must agree on the mapping or the ants steer on a shifted copy of
// their own trails, which looks exactly like bad steering and is not.
// ---------------------------------------------------------------------------
float2 fmWorldToFieldUV(float2 w, FmRec arena) { return fmWorldToFoot(w, arena) * 0.5 + 0.5; }
float2 fmFieldUVToWorld(float2 uv, FmRec arena) { return fmFootToWorld(uv * 2.0 - 1.0, arena); }

// ---------------------------------------------------------------------------
// Small shared drawing primitives, in pixels. Used by both instrument canvases so a hairline
// means the same weight in the plan strip as it does in the gait chart.
// ---------------------------------------------------------------------------
float fmSegDist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float fmLineMask(float2 p, float2 a, float2 b, float w)
{
    return 1.0 - smoothstep(w * 0.5 - 0.75, w * 0.5 + 0.75, fmSegDist(p, a, b));
}

float fmDiscMask(float2 p, float2 c, float r)
{
    return 1.0 - smoothstep(r - 0.75, r + 0.75, length(p - c));
}

float fmRingMask(float2 p, float2 c, float r, float w)
{
    return 1.0 - smoothstep(w * 0.5 - 0.75, w * 0.5 + 0.75, abs(length(p - c) - r));
}

float fmRectMask(float2 p, float2 lo, float2 hi)
{
    float2 d = max(lo - p, p - hi);
    return 1.0 - smoothstep(-0.75, 0.75, max(d.x, d.y));
}

float fmRectFrame(float2 p, float2 lo, float2 hi, float w)
{
    float2 c = (lo + hi) * 0.5, h = (hi - lo) * 0.5;
    float2 d = abs(p - c) - h;
    float sd = min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
    return 1.0 - smoothstep(w * 0.5 - 0.75, w * 0.5 + 0.75, abs(sd));
}

// Premultiplied-free "ink over" with a mask. Kept as one helper so no canvas invents its own
// blend and ends up with hairlines that darken where they cross.
float3 fmInk(float3 dst, float3 col, float m) { return lerp(dst, col, saturate(m)); }

#endif // FORMIC_HLSLI
