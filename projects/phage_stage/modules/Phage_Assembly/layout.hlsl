// Phage_Assembly / layout - the truss axonometric's title, counts, key and member card, recorded for
// the shared UI kit (ui.hlsl draws them over preview.hlsl's drawing of the real generated tubes and
// solids). Point at a member (hover.hlsl finds it): its tubes light in the drawing and the card says
// what it is - the part and the piece, its length, its truss width, its bays and how many tubes it
// makes, all from the live member record.
#include "assembly_types.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "axo.hlsli"
StructuredBuffer<PhMark> Marks:register(t0);
StructuredBuffer<float4> Hover:register(t1);
StructuredBuffer<PhMember> Mem:register(t2);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

// A member's part and piece, by its kind in the anatomy's member table (members 0-137 are box truss).
uint partOf(uint k) { return k <= 3u ? LB_N_PLATE : k <= 5u ? LB_N_SHEATH : k == 6u ? LB_N_COLLAR : k == 7u ? LB_N_CAPSID : k <= 9u ? LB_N_LEG : LB_N_BOOTH; }
uint pieceOf(uint k)
{
    return k == 1u ? LB_P_OUTER : k == 2u ? LB_P_INNER : k == 3u ? LB_P_SPOKE : k == 4u ? LB_P_UPRIGHT : k == 7u ? LB_P_EDGE
         : k == 8u ? LB_P_UPPER : k == 9u ? LB_P_LOWER : k == 11u ? LB_P_POST : LB_P_RING;
}

// a caption, a value and an optional unit; returns the width used
float capNum(uint caption, float v, int dec, uint unit, float x, float y, float s)
{
    float w = dlLabel(caption, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
    w += dlNum(v, dec, x + w, y, IL_T_VALUE * s, IL_INK, IL_LEFT);
    if (unit != 0xffffffffu) w += 3.0 * s + dlLabel(unit, x + w + 3.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    return w + 14.0 * s;
}

void memberCard(uint j, float2 p, float2 R, float s)
{
    PhMember r = Mem[j];
    uint kind = (uint)round(r.b.w);
    float len = length(r.b.xyz - r.a.xyz);
    uint bays = clamp((uint)ceil(len / (r.a.w * 1.15)), 1u, 15u);
    float2 size = float2(352.0, 62.0) * s;
    float2 o = p + 16.0 * s;
    if (o.x + size.x > R.x - 6.0) o.x = p.x - 16.0 * s - size.x;
    if (o.y + size.y > R.y - 6.0) o.y = p.y - 16.0 * s - size.y;
    float4 c = float4(o, o + size);
    dlRectEdged(c, IL_RAISE, 0.96, IL_RADIUS * s, IL_EDGE, 1.0);
    float x = c.x + 10.0 * s, y1 = c.y + 17.0 * s, y2 = c.y + 42.0 * s;
    x += dlLabel(partOf(kind), x, y1, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
    if (r.meta.w >= 0.0) x += dlInt((int)r.meta.w + 1, 1, x, y1, IL_T_VALUE * s, IL_INK, IL_LEFT) + 5.0 * s;
    dlLabel(pieceOf(kind), x + 3.0 * s, y1, IL_T_BODY * s, IL_DIM, IL_LEFT);
    float rx = c.z - 10.0 * s;
    rx -= dlInt((int)j, 1, rx, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlLabel(LB_MEMBER, rx, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    x = c.x + 10.0 * s;
    x += capNum(LB_LENGTH, len, 2, LB_M, x, y2, s);
    x += capNum(LB_TRUSS, r.a.w, 2, LB_M, x, y2, s);
    x += capNum(LB_BAYS, (float)bays, 0, 0xffffffffu, x, y2, s);
    capNum(LB_TUBES, (float)(12u + 4u * bays), 0, 0xffffffffu, x, y2, s);
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = axoS(R);
    dlBegin(R);
    float hy = 0.5 * axoHead(R) - 2.0 * s;
    float tw = dlLabel(LB_TITLE, 14.0 * s, hy, 14.0 * s, IL_INK, IL_LEFT);
    float sw = dlLabel(LB_SUBTITLE, 14.0 * s + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    // how many members, tubes and solids the structure pass generated (marks.hlsl's record at AM_REC)
    float4 n = Marks[AM_REC].fill;
    float x = R.x - 14.0 * s;
    x -= dlInt((int)n.y, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
    x -= dlLabel(LB_SOLIDS, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 18.0 * s;
    x -= dlInt((int)n.x, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
    x -= dlLabel(LB_TUBES, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 18.0 * s;
    x -= dlInt((int)n.z, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
    dlLabel(LB_MEMBERS, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);
    dlHLine(axoHead(R) - 2.0 * s, 12.0, R.x - 12.0, IL_EDGE);

    // the key, bottom left: what each stroke is, and the floor grid's pitch
    float4 key = float4(12.0, R.y - 12.0 - 28.0 * s, 12.0 + 372.0 * s, R.y - 12.0);
    dlRectEdged(key, IL_PANEL, 0.94, IL_RADIUS * s, IL_EDGE, 1.0);
    float ky = ilMid(key).y, kx = key.x + 10.0 * s;
    dlLine(float2(kx, ky), float2(kx + 18.0 * s, ky), 1.4 * s, IL_INK, 1.0);
    kx += 24.0 * s; kx += dlLabel(LB_K_CHORDS, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
    dlLine(float2(kx, ky), float2(kx + 18.0 * s, ky), 1.0 * s, IL_MID * 0.8, 1.0);
    kx += 24.0 * s; kx += dlLabel(LB_K_LACING, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
    dlBorderRect(float4(kx, ky - 5.0 * s, kx + 10.0 * s, ky + 5.0 * s), 0.0, IL_DIM, 1.0);
    kx += 16.0 * s; kx += dlLabel(LB_K_SOLIDS, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
    dlLabel(LB_K_GRID, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT);

    // the member under the pointer (hover.hlsl), or how to get one; with Tooltips off, neither (its
    // tubes still light in the drawing)
    int hm = (int)round(Hover[0].x);
    if (tooltips != 0)
    {
        if (hm >= 0 && hm < TRUSS_MEMBERS) memberCard((uint)hm, _ViewportPointerPosition * R, R, s);
        else dlLabel(LB_HINT, 14.0 * s + tw + 10.0 * s + sw + 28.0 * s, hy, IL_T_BODY * s, IL_DIM, IL_LEFT);
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
