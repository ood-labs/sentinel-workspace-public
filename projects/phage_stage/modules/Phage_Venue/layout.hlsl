// Phage_Venue / layout - the arena drawing's type, view frames and readout column, recorded for the
// shared UI kit (ui.hlsl draws them over preview.hlsl's plan and long section). Every figure is the
// live one: people and lit bars from the marks record, the hall from its parameters, the capsid top
// and kinetic maximum from the silhouette pass.
#include "../_shared/phage_venue.hlsli"
StructuredBuffer<float4> Sil : register(t0);
#include "../_shared/ph_marks.hlsli"
#include "venue_view.hlsli"
StructuredBuffer<PhMark> Marks : register(t1);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
float steelY() { return floor_level + hall_height - 2.69; }

// value then its unit, left-aligned; returns the width
float numUnit(float v, int decimals, float x, float y, float size, float3 col, uint unit)
{
    float w = dlNum(v, decimals, x, y, size, col, IL_LEFT);
    return w + 4.0 + dlLabel(unit, x + w + 4.0, y + 0.12 * size, IL_T_BODY, IL_DIM, IL_LEFT);
}

void layout()
{
    float2 R = _Resolution.xy;
    dlBegin(R);
    venueView(R);
    bool design = Sil[0].w == 260932;
    float cl = steelY() - Sil[0].y;
    bool low = design && cl < 1.0;
    float hy = 17.0;
    float tw = dlLabel(LB_TITLE, 14.0, hy, 14.0, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, 14.0 + tw + 10.0, hy, 12.0, IL_DIM, IL_LEFT);

    // the two views: plan (stage left, audience right) over the long section
    float4 pr = venuePlanRect(), sr = venueSectRect();
    dlBorderRect(ilInset(pr, -8.0), IL_RADIUS, IL_EDGE, 1.0);
    dlBorderRect(ilInset(sr, -8.0), IL_RADIUS, IL_EDGE, 1.0);
    // captions sit clear of the column marks that ride the hall walls
    dlLabel(LB_PLAN, pr.x + 8.0, pr.y + 22.0, IL_T_TITLE, IL_DIM, IL_LEFT);
    dlLabel(LB_STAGE, pr.x + 8.0, pr.w - 22.0, IL_T_CAP, IL_DIM, IL_LEFT);
    dlLabel(LB_AUDIENCE, pr.z - 8.0, pr.w - 22.0, IL_T_CAP, IL_DIM, IL_RIGHT);
    dlLabel(LB_SECTION, sr.x, 0.5 * (pr.w + sr.y), IL_T_TITLE, IL_DIM, IL_LEFT);   // in the gap, clear of the roof
    if (design)
    {
        float4 cap = Sil[1];
        float yS = sectPx(float3(0, steelY(), 0)).y, yM = sectPx(float3(0, Sil[0].y, 0)).y;
        float cx = sectPx(float3(0, 0, 0)).x, span = (2.0 * cap.y + 2.0) * gS, dx = cx + (cap.y + 1.2) * gS;
        dlLabel(LB_ROOF_STEEL, sr.z - 8.0, yS - 9.0, IL_T_CAP, IL_DIM, IL_RIGHT);
        dlLabel(LB_KINETIC_MAX, cx - span, yM - 9.0, IL_T_CAP, low ? IL_ALARM : IL_DIM, IL_LEFT);
        numUnit(cl, 1, dx + 9.0, 0.5 * (yS + yM), IL_T_VALUE, low ? IL_ALARM : IL_INK, LB_M);
    }

    // the readout column
    float4 col = float4(R.x - SIDE + 4.0, 38.0, R.x - 12.0, sr.w + 8.0);
    float4 body = dlPane(col, 1.0, LB_ROOM, false);
    float x0 = body.x + 14.0, y = body.y + 22.0;
    dlLabel(LB_PEOPLE, x0, y, IL_T_TITLE, IL_DIM, IL_LEFT);
    dlInt((int)Marks[VM_REC].fill.x, 1, x0, y + 26.0, 24.0, IL_INK, IL_LEFT);
    y += 70.0;
    dlLabel(LB_HALL, x0, y, IL_T_TITLE, IL_DIM, IL_LEFT);
    float x = x0, yv = y + 24.0;
    x += dlInt((int)round(hall_width), 1, x, yv, 16.0, IL_INK, IL_LEFT) + 6.0;
    x += dlLabel(LB_X, x, yv, IL_T_BODY, IL_DIM, IL_LEFT) + 6.0;
    x += dlInt((int)round(hall_length), 1, x, yv, 16.0, IL_INK, IL_LEFT) + 6.0;
    x += dlLabel(LB_X, x, yv, IL_T_BODY, IL_DIM, IL_LEFT) + 6.0;
    x += dlInt((int)round(hall_height), 1, x, yv, 16.0, IL_INK, IL_LEFT) + 4.0;
    dlLabel(LB_M, x, yv + 2.0, IL_T_BODY, IL_DIM, IL_LEFT);
    y += 62.0;
    dlLabel(LB_BARS_LIT, x0, y, IL_T_TITLE, IL_DIM, IL_LEFT);
    float w = dlInt((int)Marks[VM_REC].fill.y, 1, x0, y + 26.0, 24.0, IL_INK, IL_LEFT);
    dlLabel(LB_OF_96, x0 + w + 8.0, y + 29.0, IL_T_BODY, IL_DIM, IL_LEFT);
    y += 70.0;
    if (design)
    {
        dlHLine(y - 18.0, body.x + 1.0, body.z - 1.0, IL_EDGE);
        dlLabel(LB_CAPSID_TOP, x0, y, IL_T_TITLE, IL_DIM, IL_LEFT);
        numUnit(Sil[0].x - floor_level, 1, x0, y + 24.0, 16.0, IL_INK, LB_M);
        y += 62.0;
        dlLabel(LB_CLEARANCE, x0, y, IL_T_TITLE, low ? IL_ALARM : IL_DIM, IL_LEFT);
        numUnit(cl, 1, x0, y + 26.0, 24.0, low ? IL_ALARM : IL_INK, LB_M);
        // the gauge: 0 to 5 m of headroom, the 1 m minimum marked, filled to the live clearance
        float4 gauge = float4(x0, y + 50.0, body.z - 14.0, y + 56.0);
        float span = 5.0, gx = lerp(gauge.x, gauge.z, saturate(cl / span)), tx = lerp(gauge.x, gauge.z, 1.0 / span);
        dlRect(gauge, IL_WELL, 1.0, 1.5);
        dlRect(float4(gauge.xy, max(gx, gauge.x + 1.0), gauge.w), low ? IL_ALARM : IL_MID, 1.0, 1.5);
        dlVLine(tx, gauge.y - 4.0, gauge.w + 4.0, IL_INK);
        dlNum(1.0, 0, tx, gauge.w + 10.0, IL_T_CAP, IL_DIM, IL_CENTER);
        dlNum(span, 0, gauge.z, gauge.w + 10.0, IL_T_CAP, IL_DIM, IL_RIGHT);
        if (low) dlLabel(LB_TOO_LOW, x0, y + 86.0, IL_T_TITLE, IL_ALARM, IL_LEFT);
    }

    // the draughtsman's cursor: plan and section share the hall's long axis, so the pointer's z is
    // one vertical line through both views, and the inspector reads the hall at the pointer
    float2 uv = _ViewportPointerPosition, p = uv * R;
    bool inside = all(uv >= 0.0) && all(uv <= 1.0);
    bool inPlan = inside && ilIn(p, pr), inSect = inside && ilIn(p, sr);
    if (inPlan || inSect)
    {
        float z = venueZ(p.x);
        float4 hp = ilInset(pr, -8.0), hs = ilInset(sr, -8.0);
        dlDashed(float2(p.x, hp.y + 1.0), float2(p.x, hs.w - 1.0), 1.0, IL_INK, 0.45, 4.0, 3.0);
        float4 across = inPlan ? pr : sr;
        dlDashed(float2(across.x, p.y), float2(across.z, p.y), 1.0, IL_INK, 0.45, 4.0, 3.0);
        dlCircle(p, 2.5, IL_INK, 1.0);
        // the readout card (Tooltips); the crosshair above stays
        if (tooltips != 0)
        {
            float2 size = float2(236.0, 58.0);
            float2 o = p + 16.0;
            if (o.x + size.x > R.x - SIDE) o.x = p.x - 16.0 - size.x;
            if (o.y + size.y > R.y - 6.0) o.y = p.y - 16.0 - size.y;
            float4 card = float4(o, o + size);
            dlRectEdged(card, IL_RAISE, 0.96, IL_RADIUS, IL_EDGE, 1.0);
            float cx = card.x + 10.0, y1 = card.y + 17.0, y2 = card.y + 40.0;
            cx += dlLabel(LB_Z, cx, y1, IL_T_BODY, IL_DIM, IL_LEFT) + 5.0;
            cx += numUnit(z, 1, cx, y1, IL_T_VALUE, IL_INK, LB_M) + 16.0;
            if (inPlan)
            {
                float x = venueX(p.y);
                cx += dlLabel(LB_X, cx, y1, IL_T_BODY, IL_DIM, IL_LEFT) + 5.0;
                numUnit(x, 1, cx, y1, IL_T_VALUE, IL_INK, LB_M);
                float w2 = numUnit(length(float2(x, z)), 1, card.x + 10.0, y2, IL_T_VALUE, IL_INK, LB_M);
                dlLabel(LB_FROM_PHAGE, card.x + 10.0 + w2 + 6.0, y2, IL_T_BODY, IL_DIM, IL_LEFT);
            }
            else
            {
                float h = (gSB - p.y) / gS;
                cx += dlLabel(LB_HEIGHT, cx, y1, IL_T_BODY, IL_DIM, IL_LEFT) + 5.0;
                numUnit(h, 1, cx, y1, IL_T_VALUE, IL_INK, LB_M);
                float w2 = numUnit(steelY() - floor_level - h, 1, card.x + 10.0, y2, IL_T_VALUE, IL_INK, LB_M);
                dlLabel(LB_UNDER_STEEL, card.x + 10.0 + w2 + 6.0, y2, IL_T_BODY, IL_DIM, IL_LEFT);
            }
        }
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
