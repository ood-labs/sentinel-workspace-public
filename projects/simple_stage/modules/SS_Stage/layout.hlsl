// SS_Stage / layout - the axonometric's title, counts, key, every fixture's program slot and the card, recorded for
// the shared UI kit (ui.hlsl draws them over preview.hlsl's drawing of the real generated tubes, solids and fixtures).
// Point at a member or a fixture (hover.hlsl finds it): it lights in the drawing and the card says what it is, all
// from the live records.
#include "stage_types.hlsli"
#include "assembly.hlsli"
#include "../_shared/ss_marks.hlsli"
#include "axo.hlsli"
StructuredBuffer<SsMark> Marks:register(t0);
StructuredBuffer<float4> Hover:register(t1);
StructuredBuffer<SsMember> Mem:register(t2);
StructuredBuffer<SsMount> Mounts:register(t3);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

uint partOf(uint k) { return k == 1u ? LB_N_FRONT : k == 2u ? LB_N_BACK : LB_N_WALL; }

// a caption, a value and an optional unit; returns the width used
float capNum(uint caption, float v, int dec, uint unit, float x, float y, float s)
{
    float w = dlLabel(caption, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
    w += dlNum(v, dec, x + w, y, IL_T_VALUE * s, IL_INK, IL_LEFT);
    if (unit != 0xffffffffu) w += 3.0 * s + dlLabel(unit, x + w + 3.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    return w + 14.0 * s;
}

float4 cardAt(float2 p, float2 R, float s, float2 size)
{
    float2 o = p + 16.0 * s;
    if (o.x + size.x > R.x - 6.0) o.x = p.x - 16.0 * s - size.x;
    if (o.y + size.y > R.y - 6.0) o.y = p.y - 16.0 * s - size.y;
    float4 c = float4(o, o + size);
    dlRectEdged(c, IL_RAISE, 0.96, IL_RADIUS * s, IL_EDGE, 1.0);
    return c;
}

void memberCard(uint j, float2 p, float2 R, float s)
{
    SsMember r = Mem[j];
    uint kind = (uint)round(r.b.w);
    float len = length(r.b.xyz - r.a.xyz);
    bool block = kind == (uint)KIND_BLOCK;
    uint bays = trussBays(r);
    float4 c = cardAt(p, R, s, float2(372.0, 62.0) * s);
    float x = c.x + 10.0 * s, y1 = c.y + 17.0 * s, y2 = c.y + 42.0 * s;
    x += dlLabel(partOf(kind), x, y1, IL_T_TITLE * s, IL_INK, IL_LEFT) + 6.0 * s;
    x += dlLabel(LB_P_SECTION, x, y1, IL_T_BODY * s, IL_DIM, IL_LEFT) + 4.0 * s;
    x += dlInt((int)r.meta.w + 1, 1, x, y1, IL_T_VALUE * s, IL_INK, IL_LEFT) + 8.0 * s;
    dlLabel(LB_SKU_F34, x, y1, IL_T_BODY * s, IL_DIM, IL_LEFT);
    float rx = c.z - 10.0 * s;
    rx -= dlInt((int)j, 1, rx, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlLabel(LB_MEMBER, rx, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    x = c.x + 10.0 * s;
    x += capNum(LB_LENGTH, block ? r.a.w : len, 2, LB_M, x, y2, s);
    x += capNum(LB_TRUSS, r.a.w, 2, LB_M, x, y2, s);
    if (!block) x += capNum(LB_BAYS, (float)bays, 0, 0xffffffffu, x, y2, s);
    capNum(LB_TUBES, block ? 12.0 : (float)(12u + 4u * bays), 0, 0xffffffffu, x, y2, s);
}

void fixtureCard(uint slot, float2 p, float2 R, float s)
{
    SsMount f = Mounts[slot];
    uint kind = (uint)round(f.kind), fam = (uint)round(f.extra.x), idx = (uint)round(f.extra.y);
    float4 c = cardAt(p, R, s, float2(372.0, 62.0) * s);
    float x = c.x + 10.0 * s, y1 = c.y + 17.0 * s, y2 = c.y + 42.0 * s;
    uint name = fam == 0u ? LB_F_FRONT_ROW : fam == 1u ? LB_F_BACK_ROW : fam == 10u ? LB_F_TRUSS_STROBE
              : fam == 11u ? LB_F_FLOOR_STROBE : LB_F_WALL;
    x += dlLabel(name, x, y1, IL_T_TITLE * s, IL_INK, IL_LEFT) + 6.0 * s;
    dlInt((int)idx + 1, 1, x, y1, IL_T_VALUE * s, IL_INK, IL_LEFT);
    float rx = c.z - 10.0 * s;
    rx -= dlInt((int)slot, 1, rx, y1, IL_T_VALUE * s, PT_INK, IL_RIGHT) + 5.0 * s;
    dlLabel(LB_SLOT, rx, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    x = c.x + 10.0 * s;
    uint what = kind == 0u ? LB_T_HALO : kind == 1u ? (fam == 11u ? LB_T_FLOOR : LB_T_STROBE) : LB_T_BATTEN;
    x += dlLabel(what, x, y2, IL_T_BODY * s, IL_DIM, IL_LEFT) + 14.0 * s;
    capNum(LB_HEIGHT, f.position.y, 2, LB_M, x, y2, s);
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = axoS(R);
    dlBegin(R);
    float hy = 0.5 * axoHead(R) - 2.0 * s;
    float tw = dlLabel(LB_TITLE, 14.0 * s, hy, 14.0 * s, IL_INK, IL_LEFT);
    float sw = dlLabel(LB_SUBTITLE, 14.0 * s + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    // what the structure pass generated and how many fixtures the plot carries (marks.hlsl's record at AM_REC)
    float4 n = Marks[AM_REC].fill;
    float x = R.x - 14.0 * s;
    x -= dlInt((int)n.w, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
    x -= dlLabel(LB_FIXTURES, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 18.0 * s;
    x -= dlInt((int)n.y, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
    x -= dlLabel(LB_SOLIDS, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 18.0 * s;
    x -= dlInt((int)n.x, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
    x -= dlLabel(LB_TUBES, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 18.0 * s;
    x -= dlInt((int)n.z, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
    dlLabel(LB_MEMBERS, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);
    dlHLine(axoHead(R) - 2.0 * s, 12.0, R.x - 12.0, IL_EDGE);

    // every fixture's program slot, beside it, away from the truss
    int hf = (int)round(Hover[0].z);
    [loop] for (uint k = 0u; k < (uint)SS_SLOTS; k++)
    {
        SsMount f = Mounts[k];
        if (f.active < 0.5) continue;
        float3 w = axoFixturePoint(f);
        float2 q = axoAt(f.kind > 1.5 ? w : w + f.up * (f.kind < 0.5 ? 0.32 : 0.0) + float3(0, f.kind > 0.5 && f.kind < 1.5 ? 0.3 : 0, 0), R);
        if (f.kind > 1.5) q.x -= 12.0 * s;
        dlInt((int)k, 1, q.x, q.y, IL_T_CAP * s, (int)k == hf ? IL_INK : IL_DIM, f.kind > 1.5 ? IL_RIGHT : IL_CENTER);
    }

    // the key, bottom left: what each stroke is, and the floor grid's pitch
    float4 key = float4(12.0, R.y - 12.0 - 28.0 * s, 12.0 + 486.0 * s, R.y - 12.0);
    dlRectEdged(key, IL_PANEL, 0.94, IL_RADIUS * s, IL_EDGE, 1.0);
    float ky = ilMid(key).y, kx = key.x + 10.0 * s;
    dlLine(float2(kx, ky), float2(kx + 18.0 * s, ky), 1.4 * s, IL_MID, 1.0);
    kx += 24.0 * s; kx += dlLabel(LB_K_CHORDS, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
    dlLine(float2(kx, ky), float2(kx + 18.0 * s, ky), 1.0 * s, PT_RULE, 1.0);
    kx += 24.0 * s; kx += dlLabel(LB_K_LACING, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
    dlCircle(float2(kx + 5.0 * s, ky), 5.0 * s, IL_MID * 0.55, 1.0);
    kx += 16.0 * s; kx += dlLabel(LB_K_FIXTURES, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT) + 8.0 * s;
    kx += dlLabel(LB_K_SLOT, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
    dlLabel(LB_K_GRID, kx, ky, IL_T_CAP * s, IL_DIM, IL_LEFT);

    // the member or fixture under the pointer (hover.hlsl), or how to get one; with Tooltips off,
    // neither (it still lights in the drawing)
    int hm = (int)round(Hover[0].x);
    float2 pp = _ViewportPointerPosition * R;
    if (tooltips != 0)
    {
        if (hf >= 0 && hf < SS_SLOTS) fixtureCard((uint)hf, pp, R, s);
        else if (hm >= 0 && hm < TRUSS_MEMBERS) memberCard((uint)hm, pp, R, s);
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
