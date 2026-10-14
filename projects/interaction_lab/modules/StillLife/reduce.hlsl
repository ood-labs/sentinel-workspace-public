// Still Life / reduce - the transform reducer (one thread): seeds the arrangement, turns this
// cook's viewport events into drags, and writes the durable object records.
//
// Selection is the HOST's (the pick pass answers its ray queries); this pass only reads it. A
// press decides what a drag means, once, and snapshots the targets:
//   on an arrow   move the selection along that world axis   (closest point on the axis line)
//   on a ring     turn the selection about that axis          (angle swept in the ring's plane)
//   on an object  slide it - or the whole selection, if it is selected - along the table
// Every cook while the button is held re-applies the drag from the snapshot to the latest pointer
// (never accumulates), so nothing drifts; Escape restores the snapshot and ends the drag.
//
// One buffer, one writer: records 0..8 are durable (the header and eight objects - state_buffers
// serializes exactly that range); record 9 is the edit state, 10..17 the drag snapshots.
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"

#define SL_RECORD_ONLY
#include "still.hlsli"
#undef SL_RECORD_ONLY
RWStructuredBuffer<SlObject> Objs : register(u0);
#define SL_OBJECTS Objs
#include "still.hlsli"

#define R_EDIT 9u
#define R_SNAP 10u
// edit record: pos = pivot, kind = last event sequence, rot = (axis, t0 on an arrow), id = handle,
// flags = target bits | held<<8 | reset<<9, spare.xyz = the press hit (slide plane, ring start).

void seed()
{
    SlObject h = (SlObject)0;
    h.id = SL_MAGIC;
    Objs[0] = h;
    [loop] for (uint i = 1u; i <= SL_MAX; i++) Objs[i] = slDefault(i);
}

// The drag probe at the current pointer for handle h: .x = the arrow's axis parameter, or .xyz = the
// ring / slide plane hit; .w = 1 when the probe is valid.
float4 dragProbe(uint h, float3 pivot, float3 axis, float3 hit0, float3 ro, float3 rd)
{
    if (h >= G_MOVE_X && h <= G_MOVE_Z)
    {
        // closest point on the axis line to the pointer ray
        float3 w0 = pivot - ro;
        float b = dot(axis, rd), d = dot(axis, w0), e = dot(rd, w0);
        float den = 1.0 - b * b;                         // 0 when the pointer ray runs along the axis
        return float4(den > 1e-4 ? (b * e - d) / den : 0.0, 0.0, 0.0, den > 1e-4 ? 1.0 : 0.0);
    }
    float3 hit;
    float3 n = (h == G_BODY) ? float3(0.0, 1.0, 0.0) : axis;
    bool ok = slPlaneHit(ro, rd, (h == G_BODY) ? hit0 : pivot, n, hit);
    return float4(hit, ok ? 1.0 : 0.0);
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    if (Objs[0].id != SL_MAGIC) seed();

    SlObject ed = Objs[R_EDIT];
    uint lastSeq = ilEvWatermark(ed.kind);
    uint newest = lastSeq;
    uint handle = ed.id;
    uint targets = ed.flags & 0xFFu;
    bool held = (ed.flags & 0x100u) != 0u;
    bool resetWas = (ed.flags & 0x200u) != 0u;
    float3 pivot = ed.pos;
    float3 axis = ed.rot.xyz;
    float t0 = ed.rot.w;
    float3 hit0 = ed.spare.xyz;

    // the Reset Arrangement button (an ordinary parameter): reseed on its rising edge
    bool resetNow = reset_layout != 0;
    if (resetNow && !resetWas) { seed(); held = false; handle = G_NONE; }

    uint n = ilEvCount();
    [loop] for (uint i = 0u; i < n; i++)
    {
        ViewportEvent e = _ViewportEvents[i];
        if (!ilEvFresh(e.sequence, lastSeq)) continue;
        newest = ilEvAdvance(newest, lastSeq, e.sequence);

        if (ilIsPress(e, IL_BTN_LEFT))
        {
            float3 ro, rd;
            slRay(e.position, ro, rd);
            handle = G_NONE;
            targets = 0u;
            uint act = slActive();
            if (act != 0u)
            {
                SlGizmo g = slGizmoOf(Objs[act], res, s);
                handle = slGizmoHit(e.position * res, g, res, s);
                if (handle != G_NONE)
                {
                    pivot = g.pivot;
                    axis = slAxis((handle - 1u) % 3u);
                    [loop] for (uint k = 1u; k <= SL_MAX; k++)
                        if (Objs[k].kind != K_EMPTY && slSelected(Objs[k].id)) targets |= 1u << (k - 1u);
                }
            }
            if (handle == G_NONE)
            {
                float t; uint rec;
                if (slMarch(ro, rd, 96u, t, rec) && rec != 0u)
                {
                    handle = G_BODY;
                    pivot = Objs[rec].pos;
                    axis = float3(0.0, 1.0, 0.0);
                    hit0 = float3(0.0, pivot.y, 0.0);            // the slide plane's height
                    bool groupDrag = slSelected(Objs[rec].id);
                    [loop] for (uint k = 1u; k <= SL_MAX; k++)
                        if (Objs[k].kind != K_EMPTY && (k == rec || (groupDrag && slSelected(Objs[k].id)))) targets |= 1u << (k - 1u);
                }
            }
            if (handle != G_NONE)
            {
                float4 p0 = dragProbe(handle, pivot, axis, hit0, ro, rd);
                if (handle >= G_MOVE_X && handle <= G_MOVE_Z) t0 = p0.x;
                else if (handle == G_BODY) hit0 = p0.xyz;
                else { hit0 = p0.xyz; }
                held = p0.w > 0.5;
                if (!held) handle = G_NONE;
                [loop] for (uint k = 1u; k <= SL_MAX; k++)
                {
                    SlObject snap = (SlObject)0;
                    snap.pos = Objs[k].pos;
                    snap.rot = Objs[k].rot;
                    Objs[R_SNAP + k - 1u] = snap;
                }
            }
        }
        else if (ilIsRelease(e, IL_BTN_LEFT))
        {
            held = false;
            handle = G_NONE;
        }
        else if (held && (ilIsCancel(e) || ilIsKeyDown(e, IL_KEY_ESC)))
        {
            // cancel: put every target back where the press found it. Escape mid-drag arrives as
            // the host cancelling the pointer capture, not as a key (the router takes it first).
            [loop] for (uint k = 1u; k <= SL_MAX; k++)
                if ((targets & (1u << (k - 1u))) != 0u) { Objs[k].pos = Objs[R_SNAP + k - 1u].pos; Objs[k].rot = Objs[R_SNAP + k - 1u].rot; }
            held = false;
            handle = G_NONE;
        }
    }

    // apply the held drag from the snapshot to the latest pointer
    if (held && handle != G_NONE)
    {
        float3 ro, rd;
        slRay(_ViewportPointerPosition, ro, rd);
        float4 p = dragProbe(handle, pivot, axis, hit0, ro, rd);
        if (p.w > 0.5)
        {
            float3 delta = float3(0.0, 0.0, 0.0);
            float4 q = float4(0.0, 0.0, 0.0, 1.0);
            if (handle >= G_MOVE_X && handle <= G_MOVE_Z) delta = axis * (p.x - t0);
            else if (handle == G_BODY) delta = float3(p.x - hit0.x, 0.0, p.z - hit0.z);
            else
            {
                float3 v0 = hit0 - pivot, v1 = p.xyz - pivot;
                float ang = atan2(dot(cross(v0, v1), axis), dot(v0, v1));
                q = qAxis(axis, ang);
            }
            [loop] for (uint k = 1u; k <= SL_MAX; k++)
            {
                if ((targets & (1u << (k - 1u))) == 0u) continue;
                float3 sp = Objs[R_SNAP + k - 1u].pos;
                float4 sr = Objs[R_SNAP + k - 1u].rot;
                Objs[k].pos = pivot + qRot(q, sp - pivot) + delta;
                Objs[k].rot = qNorm(qMul(q, sr));
                Objs[k].pos.y = max(Objs[k].pos.y, -0.25);          // never lose an object under the floor
            }
        }
    }

    ed.kind = newest;
    ed.id = handle;
    ed.flags = (targets & 0xFFu) | (held ? 0x100u : 0u) | (resetNow ? 0x200u : 0u);
    ed.pos = pivot;
    ed.rot = float4(axis, t0);
    ed.spare = float4(hit0, 0.0);
    ed.scale = 0.0;
    ed.colour = 0.0;
    Objs[R_EDIT] = ed;
}
