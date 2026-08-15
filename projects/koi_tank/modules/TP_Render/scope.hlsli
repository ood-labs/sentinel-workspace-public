// TP_Render / scope.hlsli: shared declarations for the exploded instrument view.
//
// Every mark stands for a number another node already published: TP_Plan's tank, TP_Sim's field,
// TP_Caustics' atlas, or TP_School's records. The Scope pass reads the renderer's shared beauty
// buffer and linear ray distance, then depth-tests its geometry with the exact same camera.
#ifndef TP_SCOPE_HLSLI
#define TP_SCOPE_HLSLI

#include "../_shared/fish.hlsli"

// Ring length per fish. The trail is MEASURED history — real positions, recorded — and the
// forecast is not; see the note in splat.hlsl for why they are drawn differently.
#define TP_TRAIL   64u
#define TP_FCAST   28u

struct TpSCtl
{
    float4 a;   // (init, time, dt, cooks)
    float4 b;   // (trailHead, writeAccum, 0, 0)
};

// ---------------------------------------------------------------------------
// THE EXPLODE.
//
// Every layer keeps its true world position and is displaced along Y by a fixed multiple of the
// tank depth. Multiples, not free offsets: the stack has to stay in a legible ORDER as it opens,
// and the order is the argument the image is making — light on top, then the surface that bends
// it, then the volume the fish occupy, then the lining it all lands on.
//
// At explode = 0 every layer returns to where it truly is and the overlay registers exactly on
// the render. That is not a gimmick — it is the proof that the exploded view is showing the same
// scene, and being able to close it is what makes the open state trustworthy.
// ---------------------------------------------------------------------------
#define TP_LAYER_CAGE  0
#define TP_LAYER_CAUS  1
#define TP_LAYER_SURF  2
#define TP_LAYER_FISH  3

// EXPANSION ABOUT THE TANK CENTRE, not translation upward.
//
// The first version lifted every layer by a fixed multiple, which pushed the whole stack off the
// top of the frame: the plates ended up ABOVE the camera, and a horizontal sheet above a camera
// that is looking down is never intersected by any ray, so they silently did not exist.
//
// Expanding instead means each layer moves AWAY FROM THE MIDDLE in the direction it already sat
// — the floor and its caustics drop, the surface rises, the fish spread about the centre. The
// stack opens symmetrically, stays framed, and keeps its true physical order, which is the whole
// argument the image makes. The cage never moves: it is the reference the rest is measured
// against, and an exploded view needs one thing that stays still.
// ONE CONTROL, NOT TWO. Explode and a separate Layer Spread only ever multiplied each other, so
// between them they expressed exactly one number and gave two ways to get lost setting it. The
// travel that used to need both is baked in here; Explode alone runs closed to fully open.
#define TP_EXPLODE_SCALE 1.9

// WHAT MOVES, AND WHAT DOES NOT.
//
// The cage and the fish marks stay exactly where they are. They ANNOTATE things that are
// visibly present in the render underneath — the tank, and the fish themselves — so displacing
// them would break the correspondence that makes them mean anything: a heading vector floating
// a metre above the fish it belongs to is no longer a statement about that fish.
//
// The plates are different in kind. They are abstractions of fields, not labels on objects, so
// they have no position to betray and pulling them out of the tank is what lets you see them at
// all. Only they travel.
float tpLayerLift(int layer, float yTrue, float depth, float explode)
{
    if (layer == TP_LAYER_CAGE || layer == TP_LAYER_FISH) return 0.0;

    float centre = -depth * 0.5;
    float expand = (yTrue - centre);

    // A small extra separation so the two sheets clear the tank rather than grazing it.
    float bias = 0.0;
    if (layer == TP_LAYER_CAUS) bias = -0.30 * depth;
    else if (layer == TP_LAYER_SURF) bias = 0.30 * depth;

    return (expand + bias) * explode * TP_EXPLODE_SCALE;
}

// ---------------------------------------------------------------------------
// Projection. TP_Render writes EUCLIDEAN distance from the camera into alpha — not view-space z
// and not a normalised depth — so the overlay must compare against the same quantity or the
// occlusion will be subtly wrong everywhere except the centre of frame.
// ---------------------------------------------------------------------------
// `res` is passed in rather than read from _Resolution: this is called from a pass whose OUTPUT
// is a buffer, where _Resolution is the module's declared size and not necessarily the extent of
// the beauty texture being annotated. Projecting into the wrong extent would offset every mark.
bool tpProject(float3 wp, float2 res, out float2 sp, out float dist)
{
    float4 cp = mul(_ViewProjMatrix, float4(wp, 1.0));
    dist = length(wp - _CameraPos);
    if (cp.w <= 1e-4) { sp = float2(-1, -1); return false; }
    sp = float2(cp.x / cp.w * 0.5 + 0.5, 0.5 - cp.y / cp.w * 0.5) * res;
    return true;
}

// ---------------------------------------------------------------------------
// The accumulation buffer.
//
// Three channels, because the overlay has three kinds of mark and they must be able to overlap
// without averaging into mud: structure (the cage and the plates), measurement (trails and
// vectors), and prediction (the forecast arcs). Each resolves to its own colour downstream, so a
// forecast crossing a trail reads as two things crossing rather than as one brighter thing.
//
// Two parity halves so nothing ever has to be cleared — the same trick TP_Caustics uses. A clear
// pass over a full-resolution buffer costs more than the scatter that fills it.
// ---------------------------------------------------------------------------
// SIX channels, not three.
//
// The first three are the inked marks: structure, measurement, prediction. The last three exist
// because a transform gizmo has to be RED, GREEN and BLUE — that is the convention that makes it
// readable without a legend — and those are not colours the ink channels can express, since each
// ink is a user-chosen tint the other marks depend on. Giving the gizmo its own three channels
// lets it resolve to true RGB downstream without touching the palette.
#define TP_ACC_CH 6u
#define TP_CH_GIZ_X 3u
#define TP_CH_GIZ_Y 4u
#define TP_CH_GIZ_Z 5u

uint tpAccIndex(uint2 px, uint w, uint h, uint ch, uint parity)
{
    return ((parity * TP_ACC_CH + ch) * h + px.y) * w + px.x;
}

// THE PRODUCER STATES WHICH HALF IT FILLED, in the one element past the two halves.
//
// The consumer must NOT work the parity out from the cook counter for itself. TP_Caustics
// already measured this and left the note: the two passes observe that counter one cook apart,
// so the reader lands on the half that was just wiped and the whole overlay comes out black
// while every mark sits safely in the other half. Publishing the choice through the buffer this
// pass owns removes the question — no assumption about pass ordering can make them disagree.
uint tpAccStamp(uint w, uint h) { return 2u * TP_ACC_CH * w * h; }

#endif // TP_SCOPE_HLSLI
