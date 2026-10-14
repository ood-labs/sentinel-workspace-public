// Handles / layout - the EDITOR overlay, recorded into the draw list and drawn by `editor` over
// the program image.
//
// Each handle: a round ring of the grab radius (everything inside it grabs; handles.hlsli has the
// strip beside it the host also grabs until engine bug #174 is fixed), a spoke for its
// rotation, and its name. Hover lifts the ring from dashed to solid ink; the grabbed handle is the
// selection, so it alone takes the accent and shows its live x / y / rot. Hover and grab are
// cosmetic reads of the pointer snapshot: the host owns the drag itself. (On 0.6.3 the snapshot
// stops while the host holds a drag - no buttons, the pointer frozen at the press - so the held
// state cannot show during one: engine bug sentinel-bugs #173, see PLAN.md.)
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "handles.hlsli"

void plate(float4 r, float s) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * s); }

void drawHandle(uint i, float2 c, float rot, float r, bool hot, bool held, float2 value, float s, float2 res)
{
    float3 ink = held ? IL_ACCENT : (hot ? IL_INK : IL_MID);
    float w = held ? 2.0 : (hot ? 1.5 : 1.0);
    float dash = (hot || held) ? 0.0 : 7.0 * s;
    float2 rr = float2(r, r);
    // a dark halo under every line keeps it legible over lit floor and shadow alike
    if (hot || held) dlEllipse(c, rr, 0.0, ink, 0.07, 0.0, 0.0);
    dlEllipse(c, rr, w + 2.5, IL_FIELD, 0.40, dash, 5.0 * s);
    dlEllipse(c, rr, w, ink, (hot || held) ? 1.0 : 0.75, dash, 5.0 * s);
    // the spoke runs to the ring along the rotation
    float2 d = hdDir(rot);
    float2 tip = c + d * r;
    dlLine(c + d * 0.3 * r, tip, w + 2.5, IL_FIELD, 0.40);
    dlLine(c + d * 0.3 * r, tip, w, ink, 1.0);
    dlCircle(tip, 2.5 * s + (held ? 1.0 : 0.0), ink, 1.0);
    dlCircle(c, 1.5 * s, ink, 0.9);

    // name (and, when held or hovered, the live values) beside the ring, flipped near the edge
    bool left = c.x + r + 150.0 * s > res.x;
    float x = left ? c.x - r - 8.0 * s : c.x + r + 8.0 * s;
    float y = c.y - 0.6 * r;
    uint al = left ? IL_RIGHT : IL_LEFT;
    float nameW = ilLabelW(LB_N_LAMP + i, IL_T_TITLE * s);
    float4 pr = float4(left ? x - nameW - 8.0 * s : x - 6.0 * s, y - 10.0 * s, left ? x + 6.0 * s : x + nameW + 8.0 * s, y + 10.0 * s);
    if (hot || held)
    {
        float vs = IL_T_VALUE * s;
        float rowW = 3.0 * ilNumW(6u, vs) + 60.0 * s;
        pr = left ? float4(x - max(nameW, rowW) - 8.0 * s, pr.y, pr.z, y + 30.0 * s)
                  : float4(pr.x, pr.y, x + max(nameW, rowW) + 8.0 * s, y + 30.0 * s);
    }
    plate(pr, s);
    dlLabel(LB_N_LAMP + i, x, y, IL_T_TITLE * s, held ? IL_ACCENT : IL_INK, al);
    if (hot || held)
    {
        float vs = IL_T_VALUE * s;
        float ry = y + 18.0 * s;
        float cx = left ? pr.x + 8.0 * s : x;
        cx += dlLabel(LB_R_X, cx, ry, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
        cx += dlNum(value.x, 3, cx, ry, vs, IL_INK, IL_LEFT) + 10.0 * s;
        cx += dlLabel(LB_R_Y, cx, ry, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
        cx += dlNum(value.y, 3, cx, ry, vs, IL_INK, IL_LEFT) + 10.0 * s;
        cx += dlLabel(LB_R_ROT, cx, ry, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
        dlNum(rot, 1, cx, ry, vs, IL_INK, IL_LEFT);
    }
}

void layout()
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    dlBegin(res);

    // header plate
    float4 hr = float4(16.0 * s, 14.0 * s, 0.0, 44.0 * s);
    float tw = ilLabelW(LB_TITLE, 15.0 * s);
    float sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    hr.z = hr.x + tw + sw + 40.0 * s;
    plate(hr, s);
    float hy = ilMid(hr).y;
    dlLabel(LB_TITLE, hr.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hr.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    // the lamp's cone edges, quiet and dashed
    float2 lamp = hdUv(lamp_pos) * res;
    float half = 0.5 * cone;
    float reach = 0.22 * res.y;
    dlDashed(lamp + hdDir(lamp_rot - half) * 18.0 * s, lamp + hdDir(lamp_rot - half) * reach, 1.0, IL_INK, 0.35, 6.0 * s, 5.0 * s);
    dlDashed(lamp + hdDir(lamp_rot + half) * 18.0 * s, lamp + hdDir(lamp_rot + half) * reach, 1.0, IL_INK, 0.35, 6.0 * s, 5.0 * s);

    // the handles: hover = the nearest the host would grab (its own metric, hdHitDist; until #174
    // is fixed that reaches past the ring left and right); held = hovered with a button down
    float r = hdRingRadiusPx(res);
    float2 vals[H_COUNT] = { lamp_pos, blade_pos, prism_pos, arc_pos };
    float rots[H_COUNT] = { lamp_rot, blade_rot, prism_rot, arc_rot };
    uint hot = H_COUNT;
    float best = H_RADIUS;
    [unroll] for (uint k = 0u; k < H_COUNT; k++)
    {
        float dk = hdHitDist(_ViewportPointerPosition, vals[k]);
        if (dk <= best) { best = dk; hot = k; }
    }
    bool down = (_ViewportButtons & 3u) != 0u;
    [loop] for (uint i = 0u; i < H_COUNT; i++)
        drawHandle(i, hdUv(vals[i]) * res, rots[i], r, i == hot, i == hot && down, vals[i], s, res);

    // hint bar
    float kh = 18.0 * s;
    float x = 16.0 * s, y = res.y - 26.0 * s;
    float4 br = float4(x, y - 15.0 * s, x, y + 15.0 * s);
    float wDrag = ilLabelW(LB_K_DRAG, IL_T_CAP * s) + 12.0 * s;
    float wRdrag = ilLabelW(LB_K_RDRAG, IL_T_CAP * s) + 12.0 * s;
    br.z = x + 24.0 * s + wDrag + ilLabelW(LB_D_DRAG, IL_T_CAP * s) + wRdrag + ilLabelW(LB_D_RDRAG, IL_T_CAP * s) + ilLabelW(LB_D_UNDO, IL_T_CAP * s) + 64.0 * s;
    plate(br, s);
    x += 10.0 * s;
    dlKeycap(float4(x, y - kh * 0.5, x + wDrag, y + kh * 0.5), s, LB_K_DRAG);
    x += wDrag + 6.0 * s;
    x += dlLabel(LB_D_DRAG, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 18.0 * s;
    dlKeycap(float4(x, y - kh * 0.5, x + wRdrag, y + kh * 0.5), s, LB_K_RDRAG);
    x += wRdrag + 6.0 * s;
    x += dlLabel(LB_D_RDRAG, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 18.0 * s;
    dlLabel(LB_D_UNDO, x, y, IL_T_CAP * s, IL_MID, IL_LEFT);

    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
