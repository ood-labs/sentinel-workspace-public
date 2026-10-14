// SS_Haze / layout — the haze drawing's type, view frames, machines and readout column, recorded for the shared
// UI kit (ui.hlsl draws them over hzart's averaged field). Every figure is the live one, from hzstats: a hazer is
// drawn firing (the accent) only while its own output is in a burst.
#include "hz_grid.hlsli"
#include "haze_view.hlsli"
StructuredBuffer<float4> T : register(t0);
StructuredBuffer<float4> S : register(t1);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

// value then its unit, left-aligned; returns the width
float numUnit(float v, int decimals, float x, float y, float size, float3 col, uint unit)
{
    float w = dlNum(v, decimals, x, y, size, col, IL_LEFT);
    return w + 4.0 + dlLabel(unit, x + w + 4.0, y + 0.12 * size, IL_T_BODY, IL_DIM, IL_LEFT);
}
// a caption that sits on the field image: a quiet plate behind it so it reads over thick haze
float onImage(uint id, float x, float y, float size, uint align)
{
    float w = ilLabelW(id, size);
    float x0 = align == IL_RIGHT ? x - w : x;
    dlRect(float4(x0 - 5.0, y - 9.0, x0 + w + 5.0, y + 8.0), IL_PANEL, 0.82, 2.0);
    return dlLabel(id, x, y, size, IL_DIM, align);
}
// a box (centre, half extents) outlined in both views
void solidBox(float3 c, float3 h)
{
    float2 a = planPx(c + float3(h.x, 0, -h.z)), b = planPx(c + float3(-h.x, 0, h.z));
    dlBorderRect(float4(a, b), 1.0, IL_RULE, 1.0);
    float2 e = sectPx(c + float3(0, h.y, -h.z)), f = sectPx(c + float3(0, -h.y, h.z));
    dlBorderRect(float4(e, f), 1.0, IL_RULE, 1.0);
}
// a machine in both views: its body, the way it blows, and its number
void machine(float3 p, float3 dir, float r, bool live, int number)
{
    float3 col = live ? IL_ACCENT : IL_MID;
    float2 a = planPx(p), b = planPx(p + dir * 1.2);
    float2 e = sectPx(p), f = sectPx(p + dir * 1.2);
    dlLine(a, b, 1.5, col, 0.9);
    dlLine(e, f, 1.5, col, 0.9);
    if (number > 0)
    {
        if (live) { dlCircle(a, r, col, 1.0); dlCircle(e, r, col, 1.0); }
        else { dlRing(a, r, 1.5, col, 1.0); dlRing(e, r, 1.5, col, 1.0); }
        float side = p.x > 0.0 ? -1.0 : 1.0;           // the number sits away from the stage's centre line
        dlInt(number, 1, a.x - 9.0, a.y - side * 12.0, IL_T_CAP, live ? IL_ACCENT : IL_DIM, IL_CENTER);
    }
    else { dlDiamond(a, r, 1.5, col, 1.0); dlDiamond(e, r, 1.5, col, 1.0); }
}

void layout()
{
    float2 R = _Resolution.xy;
    dlBegin(R);
    HzDomain d = hzDomain(T[1], T[2], T[3]);
    hazeView(R, d);
    float4 s0 = S[0], s1 = S[1], s2 = S[2];
    float hy = 17.0;
    float tw = dlLabel(LB_TITLE, 14.0, hy, 14.0, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, 14.0 + tw + 10.0, hy, 12.0, IL_DIM, IL_LEFT);

    // the two views: plan (stage left, audience right) over the long section
    float4 pr = planRect(), sr = sectRect();
    dlBorderRect(ilInset(pr, -8.0), IL_RADIUS, IL_EDGE, 1.0);
    dlBorderRect(ilInset(sr, -8.0), IL_RADIUS, IL_EDGE, 1.0);
    onImage(LB_PLAN, pr.x + 10.0, pr.y + 15.0, IL_T_TITLE, IL_LEFT);
    onImage(LB_STAGE, pr.x + 10.0, pr.w - 13.0, IL_T_CAP, IL_LEFT);
    onImage(LB_AUDIENCE, pr.z - 10.0, pr.w - 13.0, IL_T_CAP, IL_RIGHT);
    float cy = 0.5 * (pr.w + sr.y) - 4.0;
    float sw = dlLabel(LB_SECTION, sr.x, cy, IL_T_TITLE, IL_DIM, IL_LEFT);
    dlLabel(field_view == 1 ? LB_SHOW_AIR : (field_view == 2 ? LB_SHOW_HEAT : LB_SHOW_HAZE), sr.x + sw + 12.0, cy, IL_T_BODY, IL_DIM, IL_LEFT);

    // what the air goes round: the deck and the DJ's booth
    solidBox(float3(0.0, d.floorY + 0.5 * HZ_DECK_TOP, 0.0), float3(HZ_DECK_HW, 0.5 * HZ_DECK_TOP, HZ_DECK_HD));
    solidBox(float3(0.0, d.floorY + 1.525, 1.15), float3(1.2, 0.525, 0.4));

    // the stage fans, then the four hazers (lit while each is in a burst)
    [unroll] for (uint k = 0; k < 2u; k++)
    {
        float side = k == 0u ? -1.0 : 1.0;
        float3 fp = float3(side * (HZ_DECK_HW - 1.0), d.floorY + HZ_DECK_TOP + 0.75, -HZ_DECK_HD + 2.2);
        if (haze_fans > 0.01) machine(fp, normalize(float3(-side * 0.32, 0.12, 1.0)), 4.5, false, 0);
    }
    [unroll] for (uint m = 0; m < HZ_MACHINES; m++)
    {
        float3 p, dir;
        hzMachine(m, d.floorY, p, dir);
        machine(p, dir, 4.0, s1[m] > 0.35 && haze_pump > 0.01, (int)m + 1);
    }

    // the readout column
    float4 col = float4(R.x - HV_SIDE + 4.0, 38.0, R.x - 12.0, sr.w + 8.0);
    float4 body = dlPane(col, 1.0, LB_ROOM, false);
    float x0 = body.x + 14.0, x1 = body.z - 14.0, y = body.y + 22.0;
    bool live = s2.w > 0.5;
    dlLabel(LB_HAZE, x0, y, IL_T_TITLE, IL_DIM, IL_LEFT);
    numUnit(s0.x, 2, x0, y + 26.0, 24.0, IL_INK, LB_UNITS);
    float w = dlLabel(LB_DENSEST, x0, y + 52.0, IL_T_BODY, IL_DIM, IL_LEFT);
    dlNum(s0.y, 2, x0 + w + 6.0, y + 52.0, IL_T_VALUE, IL_INK, IL_LEFT);
    y += 82.0;
    dlLabel(LB_AIR, x0, y, IL_T_TITLE, IL_DIM, IL_LEFT);
    numUnit(s0.z, 1, x0, y + 26.0, 24.0, IL_INK, LB_MS);
    w = dlLabel(LB_HEAT, x0, y + 52.0, IL_T_BODY, IL_DIM, IL_LEFT);
    numUnit(s2.y, 2, x0 + w + 6.0, y + 52.0, IL_T_VALUE, IL_INK, LB_K);
    y += 82.0;
    // the projection's proof: how much of the air's divergence survives the multigrid solve
    bool poor = live && s0.w > 0.25;
    dlLabel(LB_SOLVE, x0, y, IL_T_TITLE, poor ? IL_ALARM : IL_DIM, IL_LEFT);
    w = numUnit(100.0 * s0.w, 1, x0, y + 24.0, 16.0, poor ? IL_ALARM : IL_INK, LB_PCT);
    dlLabel(LB_LEFT, x0 + w + 6.0, y + 26.0, IL_T_BODY, IL_DIM, IL_LEFT);
    y += 58.0;

    dlHLine(y - 16.0, body.x + 1.0, body.z - 1.0, IL_EDGE);
    dlLabel(LB_HAZERS, x0, y, IL_T_TITLE, IL_DIM, IL_LEFT);
    y += 22.0;
    float span = 2.5 * max(haze_pump, 0.2);
    [unroll] for (uint h = 0; h < HZ_MACHINES; h++)
    {
        float o = s1[h];
        bool on = o > 0.35 && haze_pump > 0.01;
        dlInt((int)h + 1, 1, x0, y, IL_T_VALUE, on ? IL_ACCENT : IL_DIM, IL_LEFT);
        dlLabel(h < 2u ? LB_BACK : LB_FRONT, x0 + 16.0, y, IL_T_BODY, IL_DIM, IL_LEFT);
        float4 bar = float4(x0 + 66.0, y - 3.0, x1, y + 3.0);
        dlRect(bar, IL_WELL, 1.0, 1.5);
        dlRect(float4(bar.xy, max(lerp(bar.x, bar.z, saturate(o / span)), bar.x + 1.0), bar.w), on ? IL_ACCENT : IL_MID, 1.0, 1.5);
        y += 22.0;
    }
    y += 10.0;
    dlLabel(LB_TOGETHER, x0, y, IL_T_TITLE, IL_DIM, IL_LEFT);
    if (s2.x > 0.001) dlLabel(hazers_full != 0 ? LB_HELD : LB_DROP, x1, y, IL_T_BODY, IL_ACCENT, IL_RIGHT);
    float4 g = float4(x0, y + 16.0, x1, y + 22.0);
    dlRect(g, IL_WELL, 1.0, 1.5);
    if (s2.x > 0.001) dlRect(float4(g.xy, max(lerp(g.x, g.z, saturate(s2.x)), g.x + 1.0), g.w), IL_ACCENT, 1.0, 1.5);
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
// rev 3 (headers changed: the shader cache keys on this file)
