// FM_Stage / sctl.hlsl — the editor's brain.
//
// Single threaded, processing the whole batch of viewport events in order and emitting AT MOST
// ONE command per cook. That bound is deliberate: the commands travel upstream to FM_Plan
// through expressions, which sample a control output once a frame, so a pass that emitted three
// commands in one cook would have two of them silently overwritten. One per cook is a number
// the channel can actually carry.
//
// A command is a MONOTONIC COUNTER plus its arguments. FM_Plan compares the counter against the
// one it last saw and acts on the DIFFERENCE, so a dropped cook cannot lose an edit and a slow
// one cannot apply it twice — the same contract the station trigger uses.
#include "../_shared/formic.hlsli"
#include "stage.hlsli"

RWStructuredBuffer<FmStgCtl> Ctl : register(u0);
// _Tex1 — the Ground lane from FM_Render, auto-declared.
StructuredBuffer<FmRec> PlanB : register(t2);

// The world point under a pointer pixel.
//
// TWO VIEWS, ONE ANSWER. In Program view the renderer already solved this for the frame it drew
// and published it as the Ground lane, so it is a texture fetch. In Plan view the projection is
// this node's own orthographic top-down and the inverse is arithmetic. Both return world
// millimetres, so everything downstream — pick, drag, place — is written once.
bool groundAt(FmStage s, FmTop T, float2 px, out float2 w)
{
    w = float2(0, 0);

    if (((int)view) == 1)
    {
        w = fmPxToTop(T, px);
        // Outside the arena there is no substrate and nothing for a station to act on, which is
        // the same rule the Ground lane enforces for the camera view.
        float2 ah = fmArenaHalf(PlanB[FM_ARENA]);
        return abs(w.x) <= ah.x && abs(w.y) <= ah.y;
    }

    if (!fmStageInside(s, px)) return false;
    float2 uv = fmStageUV(s, px);
    float4 g = _Tex1.SampleLevel(LinearSampler, uv, 0);
    // The blue channel is the validity flag the renderer wrote. Sampled BILINEAR, so a pixel
    // straddling the horizon comes back part-valid; a full-strength test rejects those rather
    // than accepting a coordinate that is a blend of a real point and a rejected one.
    if (g.b < 0.995) return false;
    w = g.rg;
    return true;
}

// Which station is under a world point. Picked against a HANDLE, not against the reach: a reach
// is often most of the arena across and would swallow every other station inside it.
uint pickStation(float2 w, float worldPerPx)
{
    uint best = 0u;
    float bestD = 1e9;
    float grab = max(pick_px, 1.0) * max(worldPerPx, 1e-4);

    for (uint s = 0u; s < FM_STAS; s++)
    {
        FmRec r = PlanB[FM_STA_0 + s];
        if (r.active < 0.5) continue;
        float d = length(w - fmRecWorld(r, PlanB[FM_ARENA]));
        if (d < grab && d < bestD) { bestD = d; best = s + 1u; }
    }
    return best;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    FmStgCtl c = Ctl[0];

    // A persistent buffer is not guaranteed to arrive zeroed, and a non-finite command counter
    // would make FM_Plan see a change every cook forever. Discarded rather than clamped, so the
    // state can actually recover instead of being held at the bound.
    if (!(abs(c.cmd) < 1e12) || !(abs(c.sel) < 1e6)) c = (FmStgCtl)0;

    // The command is TRANSIENT in everything but the counter: act, wx and wz describe the edit
    // that was emitted, and leaving them set would be harmless but leaving `act` set while the
    // counter is unchanged tells the reader nothing. The counter alone gates.
    float startCmd = c.cmd;

    uint gw, gh;
    _Tex1.GetDimensions(gw, gh);

    FmStage stg = fmStage(_Resolution.xy, float2(max((float)gw, 1.0), max((float)gh, 1.0)) * 2.0);
    FmTop   T   = fmTopFit(float2(0, 0), _Resolution.xy, PlanB[FM_ARENA], FM_STAGE_PLAN_INSET);

    // World millimetres per pixel, measured rather than assumed. There are no derivatives in a
    // compute shader — fwidth is an X4532 here — so it is differenced by hand from two samples
    // a known distance apart, which is what a derivative is.
    float worldPerPx = 0.25;
    if (((int)view) == 1)
    {
        worldPerPx = 1.0 / max(T.scale, 1e-4);        // orthographic: exact and constant
    }
    else
    {
        float2 mid = (stg.lo + stg.hi) * 0.5;
        float2 a, b;
        if (groundAt(stg, T, mid, a) && groundAt(stg, T, mid + float2(8.0, 0.0), b))
            worldPerPx = max(length(b - a) / 8.0, 1e-4);
    }

    uint n = min((uint)_ViewportEventCount, 64u);

    // ---- POINTER
    for (uint e0 = 0u; e0 < n; e0++)
    {
        ViewportEvent ev = _ViewportEvents[e0];
        if (ev.type != 5u) continue;

        float2 px = ev.position * _Resolution.xy;
        float2 w;
        bool ok = groundAt(stg, T, px, w);
        if (ok) { c.ptrX = w.x; c.ptrZ = w.y; c.ptrOk = 1.0; }
        else if (((int)view) == 0 && !fmStageInside(stg, px)) c.ptrOk = 0.0;

        if (ev.code == 1u && ev.phase == 7u)          // click
        {
            if (ok) c.sel = (float)pickStation(w, worldPerPx);
        }
        else if (ev.code == 3u)                        // left drag
        {
            if (ev.phase == 5u)
            {
                if (ok)
                {
                    uint hit = pickStation(w, worldPerPx);
                    c.sel = (float)hit;
                    if (hit != 0u)
                    {
                        c.dragOn = 1.0;
                        // The grab offset is what stops the record snapping its centre to the
                        // cursor the instant a drag starts, which turns a nudge into a jump.
                        float2 rp = fmRecWorld(PlanB[FM_STA_0 + hit - 1u], PlanB[FM_ARENA]);
                        c.grabX = rp.x - w.x;
                        c.grabZ = rp.y - w.y;
                    }
                }
            }
            else if (ev.phase == 6u && c.dragOn > 0.5 && c.sel > 0.5 && ok)
            {
                c.act = 2.0;                            // move
                c.wx = w.x + c.grabX;
                c.wz = w.y + c.grabZ;
                c.cmd += 1.0;
            }
            else if (ev.phase != 6u) c.dragOn = 0.0;
        }
    }

    // ---- KEYS. After the pointer, so A places where the cursor is in the SAME batch of events
    // rather than one cook behind it.
    for (uint e1 = 0u; e1 < n; e1++)
    {
        ViewportEvent ev = _ViewportEvents[e1];
        if (ev.type != 4u || ev.phase != 1u) continue;
        uint k = (uint)ev.code;

        if (k == 3u) { c.sel = 0.0; }                   // C  clear
        else if (k == 1u && c.ptrOk > 0.5)              // A  place
        {
            c.act = 1.0; c.wx = c.ptrX; c.wz = c.ptrZ; c.cmd += 1.0;
        }
        else if (k == 20u && c.sel > 0.5)               // T  fire
        {
            c.act = 3.0; c.wx = c.ptrX; c.wz = c.ptrZ; c.cmd += 1.0;
        }
        else if (k == 24u && c.sel > 0.5)               // X  on/off
        {
            c.act = 4.0; c.wx = c.ptrX; c.wz = c.ptrZ; c.cmd += 1.0;
        }
        else if (k == 4u && c.sel > 0.5)                // D  delete
        {
            // Distinct from X on purpose. X MUTES a station — it stops acting but keeps its
            // kind, reach, strength and position, so you can A/B what it was doing. D removes
            // it: the record is wiped and the slot goes back on the pile for the next A.
            c.act = 5.0; c.wx = c.ptrX; c.wz = c.ptrZ; c.cmd += 1.0;
            c.sel = 0.0;
        }
    }

    // At most one command per cook, as promised above. If a drag produced several this cook,
    // the counter advanced several times but only the LAST arguments survive — which for a move
    // is exactly right, because the last position is where the cursor is.
    if (c.cmd > startCmd + 1.0) c.cmd = startCmd + 1.0;

    Ctl[0] = c;
}
