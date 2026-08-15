// FM_Scope / scope.hlsli — the instrument's vocabulary.
//
// This node draws NOTHING OF ITS OWN. Every mark stands for a number another node published:
// a gizmo is the ant's real heading frame, a trail is recorded history, a predicted path is an
// extrapolation of the measured speed and the measured turn rate, a contact link is the
// antennation value the colony computed, a foot cross is a published stance.
//
// The consequence worth stating: if a mark is in the wrong place, the mark is not wrong — one
// of those numbers is. That is what makes the overlay a diagnostic instead of a decoration.
#ifndef FM_SCOPE_HLSLI
#define FM_SCOPE_HLSLI

#include "../_shared/formic.hlsli"

// The scope's clock and its trail-sampling cursor. 8 floats / 32 bytes.
struct FmSCtl
{
    float time;
    float dt;
    float lastT;      // time of the last recorded trail sample
    float writeIdx;   // ring cursor, shared by every ant's lane
    float written;    // how many samples each lane holds
    float prevTime;   // previous _Time, for differencing
    float pad0;
    float pad1;
};

// One recorded position. 4 floats / 16 bytes.
//
// `w` is a TIMESTAMP, not a flag. Segments are validated by comparing the timestamps of their
// two endpoints rather than by ring index, because a same-cook write is not guaranteed visible
// to a later pass and comparing recorded times makes the question of which buffer generation
// was served irrelevant. w <= 0 means never written.
struct FmTrailPt
{
    float3 pos;
    float  w;
};

// ---------------------------------------------------------------------------
// HOW MANY ANTS THE INSTRUMENT COVERS — deliberately NOT the whole colony.
//
// The population went to 1024 and this number did not follow it, on purpose. Every mark here
// exists to be READ: a heading gizmo, a forecast arc, a recorded trail, six foot crosses and an
// antennation link, per ant. At 64 ants that is an instrument. At 1024 it is 47 000 segments of
// grey hatch over the whole plate, which is not a denser instrument — it is an opaque one, and
// it hides the very thing it is drawn on top of.
//
// It is also what keeps the antennation link affordable: finding each ant's nearest neighbour
// is a scan of the population, so that mark alone is SC_ANTS x population.
//
// The first SC_ANTS slots are a fair sample rather than a special group: the colony seeds and
// the emitters deal out of one shared pool in index order, so slot 40 is no more likely to be
// doing anything in particular than slot 400.
#define SC_ANTS 64u

#define SC_TRAIL_LEN 24u
#define SC_TRAIL_N   (SC_ANTS * SC_TRAIL_LEN)

// --- the segment budget. Every mark in the overlay is a screen-space quad built from one
// world-space segment, so the whole instrument is one draw call.
#define SEG_GIZMO_0 0u
#define SEG_GIZMO_N (SC_ANTS * 3u)                       // 192  three axes per ant

#define SEG_PRED_0  (SEG_GIZMO_0 + SEG_GIZMO_N)
#define SEG_PRED_N  (SC_ANTS * 8u)                       // 512  the forecast arc

#define SEG_TRAIL_0 (SEG_PRED_0 + SEG_PRED_N)
#define SEG_TRAIL_N (SC_ANTS * (SC_TRAIL_LEN - 1u))      // 1472 recorded history

#define SEG_FOOT_0  (SEG_TRAIL_0 + SEG_TRAIL_N)
#define SEG_FOOT_N  (SC_ANTS * FM_LEGS)                  // 384  one cross arm per foot

#define SEG_LINK_0  (SEG_FOOT_0 + SEG_FOOT_N)
#define SEG_LINK_N  SC_ANTS                              // 64   antennation

#define SEG_GRAD_0  (SEG_LINK_0 + SEG_LINK_N)
#define SEG_GRAD_NX 22u
#define SEG_GRAD_NY 15u
#define SEG_GRAD_N  (SEG_GRAD_NX * SEG_GRAD_NY)              // 330  the field the ants steer on

#define SEG_TOTAL   (SEG_GRAD_0 + SEG_GRAD_N)                // 2954

// Layer heights, in millimetres, lifted by the explode control. The scene is essentially flat,
// so an exploded view here separates the LANES OF INFORMATION rather than parts of an object:
// the substrate's field, then what was recorded, then what is predicted, then the frames.
#define LAY_GRAD  0.6
#define LAY_TRAIL 3.0
#define LAY_PRED  5.4
#define LAY_GIZMO 7.6

#endif // FM_SCOPE_HLSLI
