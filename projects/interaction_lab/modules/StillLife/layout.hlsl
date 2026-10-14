// Still Life / layout - the editor overlay, drawn over the outlined solve by `editor`.
//
// The gizmo belongs to the active object (the host's active selection): three arrows and three
// rings in world axes, sized to clear the object's silhouette. Axis is identity colour (X / Y / Z
// - a closed set of three, repeated on the caption's x / y / z so the readout names its handle);
// the handle under the pointer lifts to ink; the handle being dragged is the live selection and
// takes the accent. Ring halves behind the pivot are hidden lines. A caption beside the rings
// names the active object with its position and heading, and says what a press would do.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

#define SL_RECORD_ONLY
#include "still.hlsli"
#undef SL_RECORD_ONLY
StructuredBuffer<SlObject> Objs : register(t0);
#define SL_OBJECTS Objs
#include "still.hlsli"

#define R_EDIT 9u

void plate(float4 r, float s) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * s); }

float3 handleInk(uint axis, uint handle, uint hot, uint drag, bool turn)
{
    uint me = (turn ? G_TURN_X : G_MOVE_X) + axis;
    return (drag == me) ? IL_ACCENT : ((hot == me) ? IL_INK : ptId((int)axis));
}

// Ring r, segment k: one slot in each of two batches. Batch 0 lays an opaque dark keyline under
// the front half (so a mid-tone identity colour reads over a bright render; opaque, because
// translucent capsules bead where they overlap), batch 1 draws every stroke above every keyline.
// The half behind the pivot is a hidden line: every other segment, thin - dashes never touch.
void ringSegment(SlGizmo g, uint r, uint k, uint hot, uint drag, float2 res, float s, bool keyline)
{
    float a0 = (float)k * (IL_TAU / (float)SL_RING_SEG), a1 = (float)(k + 1u) * (IL_TAU / (float)SL_RING_SEG);
    float3 p0 = slRingPoint(g, r, a0), p1 = slRingPoint(g, r, a1);
    float3 s0 = slProject(p0, res), s1 = slProject(p1, res);
    if (s0.z <= 0.0 || s1.z <= 0.0) return;
    bool back = slRingBack(g, 0.5 * (p0 + p1));
    uint me = G_TURN_X + r;
    float w = (drag == me) ? 3.0 : ((hot == me) ? 2.5 : 2.0);
    if (keyline)
    {
        if (!back) dlLine(s0.xy, s1.xy, (w + 1.0) * s, IL_PANEL, 1.0);
        return;
    }
    if (back && (k & 1u) != 0u) return;
    dlLine(s0.xy, s1.xy, (back ? 1.0 : w) * s, handleInk(r, me, hot, drag, true), back ? 0.6 : 1.0);
}

void layout()
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    dlBegin(res);

    uint act = slActive();
    SlObject ed = Objs[R_EDIT];
    bool held = (ed.flags & 0x100u) != 0u;
    uint drag = held ? ed.id : G_NONE;

    // header: title, and the host selection as a count
    float4 hr = float4(16.0 * s, 14.0 * s, 0.0, 44.0 * s);
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    hr.z = hr.x + tw + sw + 40.0 * s;
    plate(hr, s);
    float hy = ilMid(hr).y;
    dlLabel(LB_TITLE, hr.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hr.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    uint count = min(_ViewportSelectionMeta.x, 64u);
    float4 cr = float4(res.x - 16.0 * s - 150.0 * s, hr.y, res.x - 16.0 * s, hr.w);
    plate(cr, s);
    if (count == 0u) dlLabel(LB_SEL_NONE, cr.z - 12.0 * s, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    else
    {
        float x = cr.z - 12.0 * s;
        x -= dlLabel(LB_SEL_N, x, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 6.0 * s;
        dlInt((int)count, 1, x, hy, IL_T_VALUE * s, IL_ACCENT, IL_RIGHT);
    }

    // the gizmo
    uint hot = G_NONE;
    if (act != 0u)
    {
        SlObject o = Objs[act];
        SlGizmo g = slGizmoOf(o, res, s);
        hot = held ? G_NONE : slGizmoHit(_ViewportPointerPosition * res, g, res, s);
        dlBatch(g.valid ? 3u * SL_RING_SEG : 0u, 1u);              // batch 0: ring keylines
        dlBatch(g.valid ? 3u * SL_RING_SEG : 0u, 0u);              // batch 1: ring strokes
        float3 c = slProject(g.pivot, res);
        if (g.valid)
        {
            [unroll] for (uint i = 0u; i < 3u; i++)
            {
                float3 e = slProject(slArrowTip(g, i), res);
                float3 b = slProject(slArrowBase(g, i), res);
                if (e.z <= 0.0 || b.z <= 0.0) continue;
                uint me = G_MOVE_X + i;
                float3 ink = handleInk(i, me, hot, drag, false);
                float w = (drag == me) ? 3.0 : ((hot == me) ? 2.5 : 2.0);
                dlLine(b.xy, e.xy, (w + 2.0) * s, IL_FIELD, 0.35);
                dlLine(b.xy, e.xy, w * s, ink, 1.0);
                dlCircle(e.xy, ((drag == me || hot == me) ? 6.0 : 5.0) * s, ink, 1.0);
            }
            dlCircle(c.xy, 3.0 * s, IL_INK, 0.9);

            // caption: name, position, heading - and what a press would do. It sits off the
            // rings' upper right (upper left when that leaves the frame), never on a handle.
            float2 csz = float2(236.0, 50.0) * s;
            float off = g.ringPx * 0.71 + 12.0 * s;
            float4 cap = float4(c.x + off, c.y - off - csz.y, c.x + off + csz.x, c.y - off);
            if (cap.z > res.x - 8.0 * s) cap.xz = float2(c.x - off - csz.x, c.x - off);
            cap.xz += max(8.0 * s - cap.x, 0.0) - max(cap.z - (res.x - 8.0 * s), 0.0);
            cap.yw += max(64.0 * s - cap.y, 0.0) - max(cap.w - (res.y - 48.0 * s), 0.0);
            plate(cap, s);
            float x = cap.x + 10.0 * s, y = cap.y + 15.0 * s;
            dlLabel(LB_N_VASE + clamp(o.kind, 1u, 5u) - 1u, x, y, IL_T_TITLE * s, held ? IL_ACCENT : IL_INK, IL_LEFT);
            uint verb = (drag != G_NONE) ? drag : hot;
            if (verb != G_NONE) dlLabel(LB_G_MX + verb - 1u, cap.z - 10.0 * s, y, IL_T_CAP * s, IL_MID, IL_RIGHT);
            float vs = IL_T_VALUE * s;
            y += 20.0 * s;
            x += dlLabel(LB_R_X, x, y, IL_T_CAP * s, ptId(0), IL_LEFT) + 4.0 * s;
            x += dlNumSigned(o.pos.x, 2, x, y, vs, IL_INK, IL_LEFT) + 9.0 * s;
            x += dlLabel(LB_R_Y, x, y, IL_T_CAP * s, ptId(1), IL_LEFT) + 4.0 * s;
            x += dlNumSigned(o.pos.y, 2, x, y, vs, IL_INK, IL_LEFT) + 9.0 * s;
            x += dlLabel(LB_R_Z, x, y, IL_T_CAP * s, ptId(2), IL_LEFT) + 4.0 * s;
            x += dlNumSigned(o.pos.z, 2, x, y, vs, IL_INK, IL_LEFT) + 9.0 * s;
            x += dlLabel(LB_R_TURN, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
            dlNum(qYawDeg(o.rot), 0, x, y, vs, IL_INK, IL_LEFT);
        }
    }
    else { dlBatch(0u, 1u); dlBatch(0u, 0u); }

    // hint bar
    float kh = 18.0 * s;
    float bx = 16.0 * s, by = res.y - 26.0 * s;
    float total = 0.0;
    [loop] for (uint k = 0u; k < 7u; k++)
        total += ilLabelW(LB_K_CLICK + k, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_D_CLICK + k, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, min(bx + total + 8.0 * s, res.x - 16.0 * s), by + 15.0 * s), s);
    bx += 10.0 * s;
    [loop] for (uint k2 = 0u; k2 < 7u; k2++)
    {
        float kw = ilLabelW(LB_K_CLICK + k2, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_D_CLICK + k2, IL_T_CAP * s);
        if (bx + kw + 6.0 * s + dw > res.x - 24.0 * s) break;
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_K_CLICK + k2);
        dlLabel(LB_D_CLICK + k2, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlSync();
    ILBatch keys = dlGetBatch(0u), rings = dlGetBatch(1u);
    if (rings.count > 0u)
    {
        float2 res = _Resolution.xy;
        float s = ilCtx(res).s;
        uint act = slActive();
        SlGizmo g = slGizmoOf(Objs[act], res, s);
        SlObject ed = Objs[R_EDIT];
        bool held = (ed.flags & 0x100u) != 0u;
        uint drag = held ? ed.id : G_NONE;
        uint hot = held ? G_NONE : slGizmoHit(_ViewportPointerPosition * res, g, res, s);
        [loop] for (uint i = gi; i < 2u * rings.count; i += IL_LAYOUT_THREADS)
        {
            bool keyline = i < rings.count;
            uint j = keyline ? i : i - rings.count;
            if (keyline) dlAt(keys, j); else dlAt(rings, j);
            ringSegment(g, j / SL_RING_SEG, j % SL_RING_SEG, hot, drag, res, s, keyline);
        }
    }
    dlEnd(gi);
}
