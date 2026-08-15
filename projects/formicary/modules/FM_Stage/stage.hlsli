// FM_Stage / stage.hlsli — the one definition of where the program image sits in the panel,
// and of how a pointer position becomes a point on the ground.
//
// Included by the pass that HIT-TESTS and the pass that DRAWS. If the two derived the stage
// rectangle independently they would disagree, and a disagreement between the picture and the
// pick reads exactly like a broken unprojection rather than like two rectangles that differ by
// a few pixels.
#ifndef FM_STAGE_HLSLI
#define FM_STAGE_HLSLI

#include "../_shared/formic.hlsli"

// How much of the frame the Plan view's arena fills. Leaves a margin for the frame, the scale
// bar and the caption, and it is a constant rather than a parameter because the pick maths and
// the drawing both derive from it and a slider between them is a way for them to disagree.
#define FM_STAGE_PLAN_INSET 0.90

// The editor's state. 16 floats / 64 bytes. The first five are the published command; the rest
// is what the editor needs to remember between cooks.
struct FmStgCtl
{
    float cmd;        // MONOTONIC. FM_Plan acts on the difference, never on the value.
    float act;        // 1 place, 2 move, 3 fire, 4 toggle
    float wx;         // command argument: world x, mm
    float wz;         // command argument: world z, mm

    float sel;        // selected station slot + 1, 0 = nothing
    float dragOn;
    float grabX;      // grab offset, world mm, so a drag does not snap the record to the cursor
    float grabZ;

    float ptrX;       // last pointer ground position, world mm
    float ptrZ;
    float ptrOk;      // 1 when the pointer was over placeable ground
    float pad0;

    float pad1, pad2, pad3, pad4;
};

// ---------------------------------------------------------------------------
// THE STAGE RECTANGLE.
//
// The program image has an intentional aspect — 1280 x 720 — and the panel has whatever aspect
// the user dragged it to. The image is FITTED, never stretched: a canonical frame distorted to
// fill a dock is no longer the frame that was composed, and every judgement made while looking
// at it would be a judgement about the wrong picture.
// ---------------------------------------------------------------------------
struct FmStage
{
    float2 lo;        // top-left of the fitted image, in panel pixels
    float2 hi;        // bottom-right
    float2 res;       // panel resolution
};

FmStage fmStage(float2 panelRes, float2 imgRes)
{
    FmStage s;
    s.res = panelRes;

    // A little breathing room, so the frame reads as a picture on a bench rather than as a
    // viewport that happens to end where the dock does.
    float2 avail = panelRes * float2(0.985, 0.985);
    float ia = max(imgRes.x, 1.0) / max(imgRes.y, 1.0);
    float pa = max(avail.x, 1.0) / max(avail.y, 1.0);

    float2 size = (pa > ia) ? float2(avail.y * ia, avail.y) : float2(avail.x, avail.x / ia);
    float2 org = (panelRes - size) * 0.5;
    s.lo = org;
    s.hi = org + size;
    return s;
}

bool fmStageInside(FmStage s, float2 px) { return all(px >= s.lo) && all(px <= s.hi); }

// Panel pixel -> program image uv. Outside the stage this runs past 0..1, which every caller
// tests for rather than saturating: a click in the letterbox is not a click at the edge of the
// frame, it is not a click on the frame at all.
float2 fmStageUV(FmStage s, float2 px) { return (px - s.lo) / max(s.hi - s.lo, 1e-3); }

#endif // FM_STAGE_HLSLI
