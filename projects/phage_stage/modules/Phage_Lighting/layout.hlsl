// Phage_Lighting / layout - the fixture canvas's type, chrome and hover, recorded for the shared UI
// kit (ui.hlsl draws it over preview.hlsl's drawing). The button and view rects come from
// lighting.hlsli, the same functions select.hlsl hit-tests, so a button draws exactly where it clicks.
// Hover (from the pointer each cook, never stored): a fixture gets a ring in BOTH views and an
// inspector card, and the group buttons it belongs to lift; a group button previews its members in
// both views before you click it.
#include "lighting.hlsli"
StructuredBuffer<float4> Sel:register(t0);
StructuredBuffer<float4> Groups:register(t1);
StructuredBuffer<float4> Show:register(t2);
StructuredBuffer<PhMount> Mounts:register(t3);
struct PhPiece{float4 a;float4 b;float4 n;float4 w;};StructuredBuffer<PhPiece> Pieces:register(t4);
StructuredBuffer<PhOptical> O:register(t5);
StructuredBuffer<PhMoverPose> Poses:register(t6);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

static int gHovChip;     // group button under the pointer, or -1 (main() computes it for every thread)

// A key and what it does, for the footer; returns the width used.
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

float segDist(float2 p, float2 a, float2 b) { float2 d = b - a; return length(p - a - d * saturate(dot(p - a, d) / max(dot(d, d), 1e-5))); }

// The fixture under the pointer in view v, or -1: the nearest mount (movers, strobes, axes) or bar
// piece within reach, measured exactly where marks.hlsl draws them.
int fixtureAt(uint v, float2 p, float2 R, float reach)
{
    int hit = -1;
    float best = reach;
    [loop] for (uint f = 0u; f < PH_SLOTS; f++)
    {
        PhMount m = Mounts[f];
        if (m.active < 0.5 || (uint)round(m.kind) == 2u) continue;
        float d = length(toView(v, m.position, R) - p);
        if (d < best) { best = d; hit = (int)f; }
    }
    uint pieces = min(_Data4_Count, (uint)(PH_BARS * PH_BAR_SEGS));
    [loop] for (uint j = 0u; j < pieces; j++)
    {
        PhPiece q = Pieces[j];
        if (q.w.z < 0.5) continue;
        float d = segDist(p, toView(v, q.a.xyz, R), toView(v, q.b.xyz, R)) + 2.0;   // a mount wins a tie
        if (d < best) { best = d; hit = (int)(PH_BAR0 + (uint)round(q.n.w)); }
    }
    return hit;
}

// "MOVER 042" style name for a slot (the same naming the programmer sheet uses); returns the width.
float slotName(uint f, float x, float y, float s)
{
    float w;
    if (f >= PH_AXIS0)
    {
        uint ax = f - PH_AXIS0;
        w = dlLabel(ax == 0u ? LB_N_BODY : (ax == 1u ? LB_N_CAPSID : LB_N_LEG), x, y, IL_T_TITLE * s, IL_INK, IL_LEFT);
        if (ax >= 2u) w += 5.0 * s + dlInt((int)ax - 1, 1, x + w + 5.0 * s, y, IL_T_VALUE * s, IL_INK, IL_LEFT);
        return w;
    }
    uint fam = f < PH_STROBE0 ? 0u : (f < PH_BAR0 ? 1u : 2u);
    uint first = fam == 0u ? PH_MOVER0 : (fam == 1u ? PH_STROBE0 : PH_BAR0);
    w = dlLabel(LB_N_MOVER + fam, x, y, IL_T_TITLE * s, IL_INK, IL_LEFT);
    return w + 5.0 * s + dlInt((int)(f - first) + 1, fam == 0u ? 3 : 2, x + w + 5.0 * s, y, IL_T_VALUE * s, IL_INK, IL_LEFT);
}

// The inspector card for slot f beside the pointer, flipped away from the canvas edges.
void inspector(uint f, float2 p, float2 R, float s)
{
    PhMount m = Mounts[f];
    uint kind = (uint)round(m.kind);
    float2 size = float2(250.0, 80.0) * s;
    float2 o = p + 18.0 * s;
    if (o.x + size.x > R.x - 6.0) o.x = p.x - 18.0 * s - size.x;
    if (o.y + size.y > R.y - 6.0) o.y = p.y - 18.0 * s - size.y;
    float4 r = float4(o, o + size);
    dlRectEdged(r, IL_RAISE, 0.96, IL_RADIUS * s, IL_EDGE, 1.0);
    float x = r.x + 10.0 * s, y = r.y + 15.0 * s;
    float w = slotName(f, x, y, s);
    dlLabel(LB_SLOT, x + w + 8.0 * s, y, IL_T_BODY * s, IL_DIM, IL_LEFT);
    dlInt((int)f, 1, x + w + 8.0 * s + ilLabelW(LB_SLOT, IL_T_BODY * s) + 4.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    if (Sel[SEL_SLOT0 + f].x > 0.5) dlLabel(LB_SELECTED, r.z - 10.0 * s, y, IL_T_CAP * s, IL_ACCENT, IL_RIGHT);
    // the groups it belongs to (the buttons that would select it)
    y += 22.0 * s;
    float gx = x;
    [loop] for (uint g = 6u; g < GROUPS; g++)
        if (inGroup(g, m) && gx < r.z - 50.0 * s) gx += dlLabel(LB_G_ALL + g, gx, y, IL_T_CAP * s, IL_MID, IL_LEFT) + 8.0 * s;
    // its live state
    y += 22.0 * s;
    if (kind == 0u)
    {
        PhOptical beam = O[f * PH_OPT_PER];
        PhMoverPose pose = Poses[f];
        dlRect(float4(x, y - 6.0 * s, x + 12.0 * s, y + 6.0 * s), ptSampleColour(beam.colour), 1.0, 2.0 * s);
        float lx = x + 20.0 * s;
        lx += dlLabel(LB_LEVEL, lx, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
        lx += dlNum(saturate(beam.intensity) * 100.0, 0, lx, y, IL_T_VALUE * s, IL_INK, IL_LEFT) + 2.0 * s;
        lx += dlLabel(LB_U_PCT, lx, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 14.0 * s;
        lx += dlLabel(LB_PAN, lx, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
        lx += dlNumSigned(pose.pan, 0, lx, y, IL_T_VALUE * s, IL_INK, IL_LEFT) + 12.0 * s;
        lx += dlLabel(LB_TILT, lx, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
        dlNumSigned(pose.tilt, 0, lx, y, IL_T_VALUE * s, IL_INK, IL_LEFT);
    }
    else if (kind == 1u)
    {
        PhStrobe st = phStrobeOf(O[PH_OPT_STROBE0 + f - PH_STROBE0]);
        dlRect(float4(x, y - 6.0 * s, x + 12.0 * s, y + 6.0 * s), ptSampleColour(st.plate_colour), 1.0, 2.0 * s);
        float lx = x + 20.0 * s;
        lx += dlLabel(LB_TUBE, lx, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
        lx += dlNum(saturate(st.tube) * 100.0, 0, lx, y, IL_T_VALUE * s, IL_INK, IL_LEFT) + 2.0 * s;
        lx += dlLabel(LB_U_PCT, lx, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 14.0 * s;
        lx += dlLabel(LB_PLATE_L, lx, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
        lx += dlNum(saturate(st.plate) * 100.0, 0, lx, y, IL_T_VALUE * s, IL_INK, IL_LEFT) + 2.0 * s;
        dlLabel(LB_U_PCT, lx, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }
    else dlLabel(kind == 2u ? LB_NOTE_BAR : LB_NOTE_AXIS, x, y, IL_T_BODY * s, IL_DIM, IL_LEFT);
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = ilCtx(R).s;
    dlBegin(R);
    bool ok = Groups[0].z > 0.5 && _Data0_Count >= PH_SLOTS;
    float x0 = 0.012 * R.x;

    // hover: the fixture under the pointer (the group button under it is gHovChip)
    float2 uv = _ViewportPointerPosition, p = uv * R;
    bool inside = all(uv >= 0.0) && all(uv <= 1.0);
    int hov = -1;
    [loop] for (uint v = 0u; v < 2u; v++)
        if (ok && inside && gHovChip < 0 && hov < 0 && ilIn(p, viewRect(v, R))) hov = fixtureAt(v, p, R, 12.0 * s);

    // title, in the strip above the buttons
    float ty = 0.5 * buttonRect(0u, R).y;
    float tw = dlLabel(LB_TITLE, x0, ty, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, x0 + tw + 10.0 * s, ty, 12.0 * s, IL_DIM, IL_LEFT);

    // group buttons: name, how many fixtures it holds, the accent tick while all of them are
    // selected; lifted while pointed at, or while the hovered fixture belongs to that group
    [loop] for (uint b = 0u; b < GROUPS; b++)
    {
        float4 r = buttonRect(b, R);
        bool on = ok && Groups[b].y > 0.5;
        bool hot = (int)b == gHovChip || (hov >= 0 && b >= 2u && inGroup(b, Mounts[hov]));
        float3 face = on ? IL_RAISE * 1.9 : (hot ? IL_RAISE * 1.5 : IL_RAISE);
        dlRectEdged(r, face, 1.0, IL_RADIUS * s, on || hot ? IL_RULE : IL_EDGE, 1.0);
        if (on) dlRect(float4(r.x + 6.0 * s, r.w - 3.0 * s, r.z - 6.0 * s, r.w - 1.0 * s), IL_ACCENT, 1.0, 1.0);
        float y = ilMid(r).y;
        dlLabel(LB_G_ALL + b, r.x + 10.0 * s, y, IL_T_BODY * s, on || hot ? IL_INK : IL_MID, IL_LEFT);
        if (ok && b != 1u) dlInt((int)Groups[b].x, 1, r.z - 9.0 * s, y, IL_T_CAP * s, hot ? IL_MID : IL_DIM, IL_RIGHT);
    }

    // the two views: a frame and a title (preview.hlsl fills them and draws the fixtures)
    [loop] for (uint vv = 0u; vv < 2u; vv++)
    {
        float4 vr = viewRect(vv, R);
        dlBorderRect(vr, IL_RADIUS * s, IL_EDGE, 1.0);
        dlLabel(vv == 0u ? LB_FRONT : LB_PLAN, vr.x + 10.0 * s, vr.y + 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
        if (vv == 1u && ok) dlLabel(LB_GRID, vr.z - 10.0 * s, vr.w - 12.0 * s, IL_T_CAP * s, IL_DIM, IL_RIGHT);
        if (!ok) dlLabel(LB_WAITING, ilMid(vr).x, ilMid(vr).y, IL_T_BODY * s, IL_DIM, IL_CENTER);
    }

    // a group button's members, previewed in both views (one batch record per slot and view)
    dlBatch(ok && gHovChip >= 2 ? 2u * PH_SLOTS : 0u, 0u);

    // the hovered fixture: a ring where it is in each view, and its card
    if (hov >= 0)
    {
        PhMount m = Mounts[hov];
        float3 at = m.position;
        [unroll] for (uint w = 0u; w < 2u; w++)
            dlRing(toView(w, at, R), 9.0 * s, 1.5 * s, IL_INK, 1.0);
    }

    // footer: the gestures, then what is selected and who has the rig
    float fy = 0.5 * (viewRect(0u, R).w + R.y);
    float hx = x0;
    hx += hint(hx, fy, s, LB_K_CLICK, LB_D_CLICK);
    hx += hint(hx, fy, s, LB_K_DRAG, LB_D_DRAG);
    hx += hint(hx, fy, s, LB_K_SHIFT, LB_D_SHIFT);
    hx += hint(hx, fy, s, LB_K_CTRL, LB_D_CTRL);
    hx += hint(hx, fy, s, LB_K_A, LB_D_A);
    hint(hx, fy, s, LB_K_ESC, LB_D_ESC);
    if (ok)
    {
        float x = R.x - x0;
        if (highlight || solo_selected)
            x -= dlLabel(highlight ? LB_HIGHLIGHT : LB_SOLO, x, fy, IL_T_TITLE * s, IL_INK, IL_RIGHT) + 18.0 * s;
        bool prog = _Data1_Count >= PH_SHOW_COUNT && Show[2].x > 0.5;
        x -= dlLabel(prog ? LB_PROGRAMMER : LB_REFERENCE, x, fy, IL_T_TITLE * s, IL_MID, IL_RIGHT) + 18.0 * s;
        x -= dlInt((int)Sel[3].x, 1, x, fy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 7.0 * s;
        dlLabel(LB_SELECTED, x, fy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);
    }
    if (tooltips != 0 && hov >= 0) inspector((uint)hov, p, R, s);   // the card (Tooltips); the rings stay
    dlFinish();
}

// Batch record i: slot i % 248 in view i / 248, ringed if it belongs to the hovered group.
void drawMember(uint i)
{
    uint f = i % PH_SLOTS, v = i / PH_SLOTS;
    PhMount m = Mounts[f];
    if (gHovChip < 2 || !inGroup((uint)gHovChip, m)) return;
    float s = ilCtx(_Resolution.xy).s;
    dlRing(toView(v, m.position, _Resolution.xy), 7.0 * s, 1.2 * s, IL_INK, 0.85);
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    float2 R = _Resolution.xy, uv = _ViewportPointerPosition;
    gHovChip = -1;
    if (all(uv >= 0.0) && all(uv <= 1.0))
        [loop] for (uint b = 0u; b < GROUPS; b++) if (ilIn(uv * R, buttonRect(b, R))) gHovChip = (int)b;
    if (gi == 0u) layout();
    dlSync();
    ILBatch bt = dlGetBatch(0u);
    [loop] for (uint i = gi; i < bt.count; i += IL_LAYOUT_THREADS) { dlAt(bt, i); drawMember(bt.user + i); }
    dlEnd(gi);
}
