// FM_Colony / colony.hlsli — definitions shared by the colony's passes.
//
// Nothing here decides anything either; walk.hlsl decides. This file holds the things that
// MORE THAN ONE pass has to agree on: how a heading becomes a frame, where a leg's neutral
// stance point is, and how the pheromone field is addressed.
#ifndef FM_COLONY_HLSLI
#define FM_COLONY_HLSLI

#include "../_shared/formic.hlsli"

// The colony's clock. 8 floats / 32 bytes. Deliberately holds NO measurement.
//
// The reason is pass scheduling. Passes are ordered by buffer dependency, not by manifest
// order, so if the clock pass also reduced the ant buffer it would depend on `ants`, while
// `walk` depends on the clock and writes `ants` — a cycle the scheduler cannot resolve. The
// clock is upstream of everything and reads nothing that anything downstream writes.
struct FmCtl
{
    float  time;        // seconds since the colony was reset
    float  dt;          // last frame interval, clamped
    float  init;        // 0 until the colony has been seeded
    float  sig;         // signature the population was built at
    float  rebuild;     // 1 on the cook the population is (re)seeded
    float  pad0;
    float  pad1;
    float  pad2;
};

// The measured aggregates. 16 floats / 64 bytes, one element, written after the ants have
// moved. Every field here is a MEASUREMENT of the population, never a restatement of a
// parameter — which is what makes it worth feeding back to the plan's flow strip.
struct FmMeas
{
    float  traffic;     // ants currently walking (not loading or unloading)
    float  laden;       // fraction of the population carrying
    float  speed;       // mean body speed, mm/s
    float  slip;        // mean per-step foot slip, mm

    float  e0;          // share of walking ants nearest trail lane 0..3
    float  e1;
    float  e2;
    float  e3;

    float  delivered;   // cumulative food delivered to the nest
    float  maxSlip;     // worst single foot slip this cook
    float  contact;     // mean antennation contact
    float  offTrail;    // fraction of walking ants not near any lane

    float  pad0;
    float  pad1;
    float  pad2;
    float  pad3;
};

// ---------------------------------------------------------------------------
// THE STATION STATE. 16 floats / 64 bytes, one per station plus a summary element at
// FM_STAS. FM_Plan owns what a station IS; this is what it has DONE, which is the colony's to
// know. Written by the single-threaded `sta` pass.
//
// WHY A RELEASE LIST AND NOT A PROBABILITY. An emitter owes a fractional number of ants each
// cook and the pool of dormant slots is shared between all of them. Letting each dormant ant
// roll a die needs the dormant count, which no single ant knows; letting each emitter claim a
// range of indices double-books two emitters onto the same slot. So one single-threaded pass
// that can see the whole population picks the exact slots, names them, and every emitter's
// arithmetic is settled before any ant looks. It costs one cook of latency on a trigger, which
// at 60 Hz is 16 ms, and it is exact.
// ---------------------------------------------------------------------------
#define FM_STA_REL 8u          // most a single station may release in one cook

struct FmSta
{
    float lastTrig;   // trigger counter this station was last seen at
    float accum;      // fractional ants owed, carried between cooks
    float live;       // MEASURED: ants currently owned by this station
    float relCount;   // how many of rel[] are valid this cook

    float rel[FM_STA_REL];   // ant indices to release, this cook only

    float served;     // cumulative ants released, or swallowed for a sink
    float pad0;
    float pad1;
    float pad2;
};

// Summary element, at index FM_STAS. The pool is a shared resource and the readouts that matter
// are about the pool, not about any one station.
#define FM_STA_SUM  FM_STAS
#define FM_STA_ELEMS (FM_STAS + 1u)

// The gait history sample. 8 floats / 32 bytes. 256 of them make the Hildebrand chart.
struct FmGait
{
    float t;         // capture time
    float bits;      // asfloat of a 6-bit stance mask, leg 0 in bit 0
    float slip;      // worst leg slip in this sample
    float speed;     // body speed
    float turn;      // signed yaw rate
    float lp0;       // group 0 local phase, for the cycle marker
    float pad0;
    float pad1;
};

// The ring holds FM_GAIT_HIST samples in elements 1..FM_GAIT_HIST; element 0 is the header,
// where `t` carries the write cursor and `bits` the number of samples written so far. The pass
// that owns the ring owns its cursor too — a producer has to state what it did in the buffer it
// owns, rather than letting the consumer re-derive it from a clock they observe a cook apart.
#define FM_GAIT_HIST 256u

// ---------------------------------------------------------------------------
// Heading frame. An ant walks on a plane, so its frame is fully determined by one horizontal
// heading — there is no roll to carry and no up vector to lose.
// ---------------------------------------------------------------------------
float2 fmRot(float2 v, float2 fwd)
{
    // fwd is unit. Local +y is forward, local +x is the ant's right.
    float2 right = float2(fwd.y, -fwd.x);
    return right * v.x + fwd * v.y;
}

// ---------------------------------------------------------------------------
// LEG GEOMETRY, in body lengths, transcribed off the photograph.
//
// A fire ant's legs are not evenly spread: the front pair reaches forward and sits close in,
// the middle pair is the widest, and the rear pair is the longest and trails behind. Getting
// this wrong is the difference between an ant and a spider, and it is visible instantly from
// above — which is the view this whole show is in.
// ---------------------------------------------------------------------------
float3 fmLegHome(uint leg, float bodyLen)
{
    uint side = leg / 3u;              // 0 = left, 1 = right
    uint pairIdx = leg % 3u;           // 0 = front, 1 = middle, 2 = rear
    float sgn = (side == 0u) ? -1.0 : 1.0;

    float lat, fore;
    // Tightened TWICE, and the second pass is the one that fixed it.
    //
    // The first pass aimed for "a footprint about one and a half body lengths across" and then
    // set the middle pair at 0.82 either side — which is 1.64 across, wider than the target it
    // was written to hit and wider than the animal is long. Combined with renderer bones that
    // were 26-35% longer than the span they had to cover, the knees towered and jutted and the
    // whole animal read as a spider from above, which is the one view this show is in.
    //
    // A fire ant worker's stance is TIGHT: the feet land inside a footprint about 1.05 body
    // lengths across, and the legs are visibly shorter relative to the body than any spider's.
    //
    // These are the JUDGED values, baked in from a side-by-side at a fixed macro camera, so
    // Leg Length = 1.0 is the shipped animal and the slider reads as a relative adjustment
    // rather than as a correction you have to remember to apply.
    if (pairIdx == 0u)      { lat = 0.374; fore =  0.357; }  // front: forward and tucked in
    else if (pairIdx == 1u) { lat = 0.527; fore =  0.017; }  // middle: the widest stance
    else                    { lat = 0.493; fore = -0.374; }  // rear: longest and trailing

    return float3(sgn * lat * bodyLen * max(leg_spread, 0.2),
                  0.0,
                  fore * bodyLen * max(leg_spread, 0.2));
}

// How far a tarsus may sit from its neutral point before the leg has run out of reach. Past
// this the foot MUST be picked up early, and the distance it gets dragged is the slip the gait
// chart reports.
float fmLegReach(uint leg, float bodyLen)
{
    uint pairIdx = leg % 3u;
    // Pulled in with the stance. A generous reach lets a tarsus trail a long way behind its
    // neutral point before the leg is picked up, and a foot left far behind the body is read as
    // a long leg just as surely as a wide stance is. Still comfortably above half a stride
    // (0.26 body lengths at the shipped Stride of 0.52), which is the floor below which a
    // planted foot would be FORCED to slide every step.
    float k = (pairIdx == 2u) ? 0.527 : ((pairIdx == 1u) ? 0.459 : 0.425);
    return k * bodyLen * max(leg_spread, 0.2);
}

// ---------------------------------------------------------------------------
// The pheromone field.
//
//   R  FOOD scent, laid by laden ants on the way home. This is the recruiting trail.
//   G  HOME scent, laid by outbound ants. This is what a laden ant follows back.
//   B  substrate occlusion, baked from the plan's obstacles.
//   A  recent occupancy, so a crowded trail can be avoided and the renderer can stain the
//      ground where the traffic actually was.
//
// Addressed through fmWorldToFieldUV so the colony, the renderer and the scope cannot end up
// reading shifted copies of the same trails — which would look exactly like bad steering and
// would not be.
// ---------------------------------------------------------------------------
#define FM_CH_FOOD 0
#define FM_CH_HOME 1

#endif // FM_COLONY_HLSLI
