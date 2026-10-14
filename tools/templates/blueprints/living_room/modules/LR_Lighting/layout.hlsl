// LR_Lighting / layout - the lighting desk's type and chrome, recorded for the shared UI kit (ui.hlsl
// draws it over preview.hlsl's plan): the title row with the records the desk reads and emits, the
// plan plate's frame and caption, the control pane with the four sliders drawn in the host
// controls' own rects (UI_RECT_*) from the parameters they set, the light-type legend in the
// records' own colours, and an inspector for the light under the pointer. Hovering a light lifts
// the slider that sets it; hovering a slider rings the lights it sets. Geometry comes from
// desk.hlsli, the functions the drawing uses. Hover is read from the pointer and never stored.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "desk.hlsli"

StructuredBuffer<LightRecord> Lights : register(t0);
// slots 1 and 2 bind the Architecture and Furnishings PNodes (data:0, data:1): only their counts
// (_Data0_Count, _Data1_Count) are read here

#define NO_LIGHT 0xFFFFu

// Type that sits over the plan gets a plate (the plan stays faintly visible through it).
void plate(float4 r, float s) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * s); }

// The width dlNum will set a number at.
float numW(float v, int decimals, float size) { return ilNumW(ilFormat(v, decimals, 1, false).n, size); }

// A key and what it does; returns the width used.
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
}
float hintW(uint key, uint does, float s) { return ilLabelW(key, IL_T_CAP * s) + 18.0 * s + ilLabelW(does, IL_T_CAP * s); }

// The four parameters the sliders set, and where each sits in its range (the manifest's ranges).
float sliderValue(uint c)
{
    return c == 0u ? daylight_intensity : (c == 1u ? practical_intensity : (c == 2u ? ambient_fill : shadow_softness));
}
float sliderNorm(uint c)
{
    float lo = c == 3u ? 0.02 : 0.0;
    float hi = c == 0u ? 3.0 : (c == 1u ? 4.0 : (c == 2u ? 1.5 : 1.0));
    return saturate((sliderValue(c) - lo) / (hi - lo));
}
// What emit_lights.hlsl scales a lamp's practical intensity by (1 for the others).
float lampFactor(uint light) { return light == 3u ? 0.78 : (light == 4u ? 0.62 : 1.0); }
uint lightType(float typeId) { return typeId < 0.5 ? 0u : (ldPractical(typeId) ? 1u : 2u); }

// A count right-aligned at x with its caption before it, when it fits right of `limit`; returns
// the x the next pair ends at (unchanged when this one was dropped).
float countPair(float x, float y, float s, uint caption, uint n, bool missing, float limit)
{
    float val = IL_T_VALUE * s, cap = IL_T_TITLE * s;
    float w = numW((float)n, 0, val) + 6.0 * s + ilLabelW(caption, cap);
    if (x - w < limit) return x;
    x -= dlInt((int)n, 1, x, y, val, missing ? IL_ALARM : IL_INK, IL_RIGHT) + 6.0 * s;
    x -= dlLabel(caption, x, y, cap, IL_DIM, IL_RIGHT);
    return x - 20.0 * s;
}

// The inspector: which light, its type, and its live values; SET BY names the slider behind it.
void card(float2 ptr, uint i, LightRecord L, float s, float4 lim)
{
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, rowH = 16.0 * s;
    float2 size = float2(246.0 * s, 36.0 * s + 5.0 * rowH);
    float x0 = ptr.x + 18.0 * s;
    if (x0 + size.x > lim.z) x0 = ptr.x - 18.0 * s - size.x;
    float y0 = ptr.y + 14.0 * s;
    if (y0 + size.y > lim.w) y0 = ptr.y - 14.0 * s - size.y;
    x0 = clamp(x0, lim.x, max(lim.z - size.x, lim.x));
    y0 = clamp(y0, lim.y, max(lim.w - size.y, lim.y));
    float4 r = float4(x0, y0, x0 + size.x, y0 + size.y);
    dlRectEdged(r, IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);

    float hy = r.y + 15.0 * s;
    float3 own = ptSampleColour(L.color);
    dlRing(float2(r.x + 15.0 * s, hy), 4.5 * s, 1.5 * s, own, 1.0);
    dlCircle(float2(r.x + 15.0 * s, hy), 1.5 * s, own, 1.0);
    dlLabel(LB_L_0 + i, r.x + 26.0 * s, hy, IL_T_BODY * s, IL_INK, IL_LEFT);
    dlLabel(LB_T_0 + lightType(L.type_id), r.z - 10.0 * s, hy, cap, IL_DIM, IL_RIGHT);
    dlHLine(r.y + 29.0 * s, r.x + 1.0, r.z - 1.0, IL_EDGE);

    float xc = r.x + 10.0 * s, xv = r.x + 84.0 * s;
    float y = r.y + 29.0 * s + 0.5 * rowH + 3.0 * s;
    [loop] for (uint k = 0u; k < 5u; k++)
        dlLabel(LB_I_0 + k, xc, y + k * rowH, cap, IL_DIM, IL_LEFT);
    dlNum(L.intensity, 2, xv, y, val, IL_INK, IL_LEFT);
    y += rowH;
    float x = xv + dlNum(L.position.y, 2, xv, y, val, IL_INK, IL_LEFT) + 3.0 * s;
    dlLabel(LB_M, x, y, cap, IL_DIM, IL_LEFT);
    y += rowH;
    x = xv + dlNum(L.range, 2, xv, y, val, IL_INK, IL_LEFT) + 3.0 * s;
    dlLabel(LB_M, x, y, cap, IL_DIM, IL_LEFT);
    y += rowH;
    dlNum(L.softness, 2, xv, y, val, IL_INK, IL_LEFT);
    y += rowH;
    x = xv + dlLabel(LB_S_0 + ldDriver(i), xv, y, cap, IL_INK, IL_LEFT) + 8.0 * s;
    if (lampFactor(i) < 1.0)
    {
        x += dlLabel(LB_TIMES, x, y, cap, IL_DIM, IL_LEFT) + 3.0 * s;
        dlNum(lampFactor(i), 2, x, y, val, IL_INK, IL_LEFT);
    }
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = ldUiScale(R);
    dlBegin(R);
    float4 plan = ldPlan(R), desk = ldDesk(R);
    float pad = ldPad(R), ppw = ldPpw(plan);
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, title = IL_T_TITLE * s;

    // the emitted records: how many are live, and of which type
    uint nLive = 0u, packed = 0u;
    [loop] for (uint q = 0u; q < 6u; q++)
    {
        LightRecord L = Lights[q];
        if (L.enabled < 0.5) continue;
        nLive++;
        packed += 1u << (8u * lightType(L.type_id));
    }
    bool context = _Data0_Count > 0u && _Data1_Count > 0u;

    // title row; on the right, the records the desk reads and the records it emits
    float ty = 0.5 * plan.y;
    float tw = dlLabel(LB_TITLE, pad, ty, 14.0 * s, IL_INK, IL_LEFT);
    float sx = pad + tw + 10.0 * s;
    float sw = dlLabel(LB_SUBTITLE, sx, ty, 12.0 * s, IL_DIM, IL_LEFT);
    float limit = sx + sw + 24.0 * s;
    float rx = R.x - pad;
    rx = countPair(rx, ty, s, LB_LIGHTS, nLive, nLive == 0u, limit);
    rx = countPair(rx, ty, s, LB_FURN, _Data1_Count, _Data1_Count == 0u, limit);
    countPair(rx, ty, s, LB_ARCH, _Data0_Count, _Data0_Count == 0u, limit);

    // the plan plate
    dlBorderRect(plan, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(LB_PLAN, plan.x + 10.0 * s, plan.y + 14.0 * s, title, IL_DIM, IL_LEFT);
    dlLabel(LB_GRID, plan.z - 10.0 * s, plan.w - 14.0 * s, cap, IL_DIM, IL_RIGHT);
    if (!context) dlLabel(LB_WAITING, ilMid(plan).x, ilMid(plan).y, IL_T_BODY * s, IL_DIM, IL_CENTER);

    // the light under the pointer: the nearest drawn mark (its dot or its ring) within reach
    float2 uvp = _ViewportPointerPosition;
    float2 ptr = uvp * R;
    bool over = all(uvp >= 0.0) && all(uvp <= 1.0) && ilIn(ptr, plan);
    uint hot = NO_LIGHT;
    if (over)
    {
        float2 w = ldWorld(ptr, plan);
        float best = 10.0 * s;
        [loop] for (uint h = 0u; h < 6u; h++)
        {
            LightRecord L = Lights[h];
            if (L.enabled < 0.5) continue;
            float d = length(w - L.position.xz);
            float dm = min(d, abs(d - ldRing(L.type_id))) * ppw;
            if (dm < best) { best = dm; hot = h; }
        }
    }

    // the control pane: the four sliders, each with its name and value over it
    float4 body = dlPane(desk, s, LB_CONTROLS, false);
    float4 head = ilPaneHead(desk, s);
    float dw = hintW(LB_K_DRAG, LB_D_DRAG, s);
    if (head.z - 10.0 * s - dw > head.x + 10.0 * s + ilLabelW(LB_CONTROLS, title) + 16.0 * s)
        hint(head.z - 10.0 * s - dw, ilMid(head).y, s, LB_K_DRAG, LB_D_DRAG);
    float4 rects[4] = { UI_RECT_DAYLIGHT, UI_RECT_PRACTICAL, UI_RECT_AMBIENT, UI_RECT_SOFTNESS };
    uint link = (hot != NO_LIGHT) ? ldDriver(hot) : 4u;   // the slider that sets the hovered light
    uint ringed = 4u;                                      // the slider under the pointer or in hand
    float lastY = body.y;
    [loop] for (uint c = 0u; c < 4u; c++)
    {
        float4 r = ilCtlRect(rects[c], R);
        bool hc = ilCtlHot(c), dc = ilCtlDown(c), lit = c == link;
        if ((hc || dc) && ringed == 4u) ringed = c;
        float cy = r.y - 8.0 * s;
        dlLabel(LB_S_0 + c, r.x, cy, cap, (hc || dc || lit) ? IL_INK : IL_DIM, IL_LEFT);
        dlNum(sliderValue(c), 2, r.z, cy, val, dc ? IL_ACCENT : IL_INK, IL_RIGHT);
        dlSlider(r, s, sliderNorm(c), hc || lit, dc);
        lastY = max(lastY, r.w);
    }

    // the legend: each type in its records' own colour, with how many are live (the hovered
    // light's type lifts to ink)
    float ly = body.w - 14.0 * s, lcy = ly - 20.0 * s;
    if (lcy - 8.0 * s > lastY + 6.0 * s)
    {
        float lx = body.x + 14.0 * s;
        dlLabel(LB_TYPES, lx, lcy, title, IL_DIM, IL_LEFT);
        [loop] for (uint t = 0u; t < 3u; t++)
        {
            uint n = (packed >> (8u * t)) & 255u;
            if (lx + 20.0 * s + ilLabelW(LB_T_0 + t, cap) + numW((float)n, 0, val) > body.z - 8.0 * s) break;
            float3 own = ptSampleColour(Lights[t == 0u ? 0u : (t == 1u ? 1u : 5u)].color);
            dlRing(float2(lx + 5.0 * s, ly), 4.5 * s, 1.5 * s, own, 1.0);
            dlCircle(float2(lx + 5.0 * s, ly), 1.5 * s, own, 1.0);
            lx += 15.0 * s;
            bool hotType = hot != NO_LIGHT && lightType(Lights[min(hot, 5u)].type_id) == t;
            lx += dlLabel(LB_T_0 + t, lx, ly, cap, hotType ? IL_INK : IL_DIM, IL_LEFT) + 5.0 * s;
            lx += dlInt((int)n, 1, lx, ly, val, IL_INK, IL_LEFT) + 18.0 * s;
        }
    }

    // the plan's marks: the lights a slider in hand sets, and the hovered light
    dlClip(plan);
    if (ringed != 4u)
        [loop] for (uint g = 0u; g < 6u; g++)
        {
            LightRecord L = Lights[g];
            if (L.enabled < 0.5 || !ldDrives(ringed, g)) continue;
            dlRing(ldPx(L.position.xz, plan), ldRing(L.type_id) * ppw + 4.0 * s, 1.0, IL_MID, 1.0);
        }
    if (hot != NO_LIGHT)
    {
        LightRecord L = Lights[hot];
        float2 c = ldPx(L.position.xz, plan);
        dlRing(c, ldRing(L.type_id) * ppw + 3.5 * s, 1.5 * s, IL_INK, 1.0);   // outside its own ring
        dlRing(c, 4.5 * s, 1.5 * s, IL_INK, 1.0);
    }
    dlClipReset();

    // the plan's verb, and the inspector last, over everything
    float fy = plan.w - 14.0 * s, fx = plan.x + 14.0 * s;
    float hw = hintW(LB_K_HOVER, LB_D_HOVER, s);
    if (fx + hw + 24.0 * s < plan.z - 10.0 * s - ilLabelW(LB_GRID, cap))
    {
        plate(float4(plan.x + 4.0 * s, fy - 12.0 * s, fx + hw + 10.0 * s, fy + 12.0 * s), s);
        hint(fx, fy, s, LB_K_HOVER, LB_D_HOVER);
    }
    if (hot != NO_LIGHT) card(ptr, hot, Lights[hot], s, ilInset(plan, 6.0 * s));
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
