// light_layout.hlsli -- the ONE layout of BR_Light's canvas, shared by the reducer (light.hlsl), the
// per-pixel plate (plate.hlsl) and the draw list (layout.hlsl), so what you see is what you hit.
// Output pixels throughout, scaled by the Interaction Lab kit's ui scale (ilCtx).
//
//   +-----------------------------------+----------------------------+
//   | title strip: time, sun, lights on                              |
//   +-----------------------------------+----------------------------+
//   | SUN PATH (azimuth x elevation,    |                            |
//   |  N . E . S . W . N), windows and  |  WHERE THE LIGHT LANDS:    |
//   |  canopy mapped onto the sky       |  sun patches on the floor, |
//   +-----------------------------------+  lamp light pools          |
//   | DAY: 0h ... 24h timeline          |  (isolux rings)            |
//   +-----------------------------------+                            |
//   | LIGHTS: readout + chips | rack    |                            |
//   +-----------------------------------+----------------------------+
//
// Include after br_records / br_light_defs (the sun path is brSolarPosition's).
#ifndef LIGHT_LAYOUT_HLSLI
#define LIGHT_LAYOUT_HLSLI

#include "../_shared/ui/il_core.hlsli"

#define LIGHT_ROLES 6          // five lamp roles + the fire
#define LIGHT_RING_E 0.35      // the floor illuminance of the middle ring, the one you drag
#define INSP_H 226.0           // the LIGHTS pane, ui px
// the handle a drag holds (the editor record's dims.x): the reducer sets it, the layout shows it
#define H_NONE 0
#define H_SUN  1
#define H_DAY  2
#define H_RING 3

struct LLayout
{
    float2 res;
    float s;             // ui scale (1 at 1280 x 720)
    float4 head;         // the title strip
    float4 chartR, chartBody;
    float4 dayR, dayBody;
    float4 inspR, inspBody;
    float4 planR, planBody;
    float scale;         // plan px per metre
    float2 o;            // pixel of world (x0, z1)
    float x0, z1;
};

LLayout lLayout(float2 res, BRRoom r)
{
    LLayout L;
    L.res = res;
    L.s = ilCtx(res).s;
    float m = ilSnap(10.0 * L.s), hh = ilSnap(IL_HEADER * L.s);
    L.head = float4(0.0, 0.0, res.x, ilSnap(36.0 * L.s));
    float split = floor(res.x * 0.56);
    float4 left = float4(m, L.head.w, split - 0.5 * m, res.y - m);
    L.planR = float4(split + 0.5 * m, L.head.w, res.x - m, res.y - m);
    L.inspR = ilCutBottom(left, ilSnap(INSP_H * L.s));
    left.w -= m;
    L.dayR = ilCutBottom(left, ilSnap(72.0 * L.s));
    left.w -= m;
    L.chartR = left;
    L.chartBody = L.chartR; ilCutTop(L.chartBody, hh);
    L.dayBody = L.dayR;     ilCutTop(L.dayBody, hh);
    L.inspBody = L.inspR;   ilCutTop(L.inspBody, hh);
    L.planBody = L.planR;   ilCutTop(L.planBody, hh);
    float W = r.x1 - r.x0 + 2.0 * r.T, D = r.z1 - r.z0 + 2.0 * r.T;
    float pad = 26.0 * L.s;
    float2 avail = ilSize(L.planBody) - 2.0 * pad;
    L.scale = max(min(avail.x / W, avail.y / D), 1.0);
    float2 c = ilMid(L.planBody);
    L.x0 = r.x0; L.z1 = r.z1;
    L.o = c - float2((r.x1 - r.x0) * 0.5, (r.z1 - r.z0) * 0.5) * L.scale;
    return L;
}

bool lInRect(float2 p, float4 r, float pad) { return p.x >= r.x - pad && p.x <= r.z + pad && p.y >= r.y - pad && p.y <= r.w + pad; }
float2 lPlanPx(LLayout L, float2 xz) { return float2(L.o.x + (xz.x - L.x0) * L.scale, L.o.y + (L.z1 - xz.y) * L.scale); }
float2 lPlanWorld(LLayout L, float2 px) { return float2(L.x0 + (px.x - L.o.x) / L.scale, L.z1 - (px.y - L.o.y) / L.scale); }

// ---- sun-path chart: azimuth 0..360 (N E S W N) left to right, elevation 0..80 bottom to top
float4 lChartPlot(LLayout L)
{
    return float4(L.chartBody.x + 30.0 * L.s, L.chartBody.y + 18.0 * L.s, L.chartBody.z - 12.0 * L.s, L.chartBody.w - 22.0 * L.s);
}
#define CHART_EL_MAX 1.3962634      // 80 degrees
float2 lChartPx(LLayout L, float az, float el)
{
    float4 p = lChartPlot(L);
    float u = az / 6.2831853;
    float v = el / CHART_EL_MAX;
    return float2(lerp(p.x, p.z, u), lerp(p.w, p.y, v));
}
float2 lChartAzEl(LLayout L, float2 px)
{
    float4 p = lChartPlot(L);
    return float2((px.x - p.x) / (p.z - p.x) * 6.2831853, (p.w - px.y) / (p.w - p.y) * CHART_EL_MAX);
}
// a world direction -> chart azimuth (with the building's compass bearing) and elevation
float2 dirAzEl(float3 d, float compassDeg)
{
    float az = (abs(d.x) + abs(d.z) > 1e-7) ? atan2(d.x, d.z) : 0.0;
    az = az + radians(compassDeg);
    az = az - 6.2831853 * floor(az / 6.2831853);
    return float2(az, asin(clamp(d.y, -1.0, 1.0)));
}
// The time on today's path whose sun is nearest px (a press in the chart grabs the sun there; the
// layout previews the same answer under the pointer).
float lSunTimeAt(LLayout L, float2 px, float doy, float lat, float2 sr, float fallback)
{
    float bestD = 1e9, bestT = fallback;
    [loop] for (int si = 0; si <= 96; si++)
    {
        float t = lerp(max(sr.x - 0.6, 0.0), min(sr.y + 0.6, 24.0), (float)si / 96.0);
        float2 ea = brSolarPosition(t, doy, lat);
        // the chart is drawn in true compass azimuth (the canvas maps windows into it)
        float az = fmod(ea.y + 6.2831853 * 2.0, 6.2831853);
        float2 sp = lChartPx(L, az, max(ea.x, -0.02));
        float dd = length(sp - px);
        if (dd < bestD) { bestD = dd; bestT = t; }
    }
    return bestT;
}

// ---- day timeline: 0..24 h, hour numbers above it
float4 lDayTrack(LLayout L)
{
    return float4(L.dayBody.x + 14.0 * L.s, L.dayBody.y + 22.0 * L.s, L.dayBody.z - 14.0 * L.s, L.dayBody.w - 10.0 * L.s);
}
float lDayX(LLayout L, float h) { float4 t = lDayTrack(L); return lerp(t.x, t.z, h / 24.0); }
float lDayH(LLayout L, float px) { float4 t = lDayTrack(L); return (px - t.x) / (t.z - t.x) * 24.0; }

// ---- the LIGHTS pane: the light rack on the right (a row per lamp role and the fire; a row
// selects its light, the switch at its right end turns it on or off), the readout and 2 x 2 chips
// on the left
#define RACK_ROWS 6
float4 lRowRect(LLayout L, int k)
{
    float pad = 10.0 * L.s, w = 250.0 * L.s, pitch = ilSnap(30.0 * L.s);
    float x1 = L.inspBody.z - pad, y0 = L.inspBody.y + 8.0 * L.s + (float)k * pitch;
    return float4(x1 - w, y0, x1, y0 + pitch - ilSnap(2.0 * L.s));
}
float4 lRowSwitch(LLayout L, int k)
{
    float4 r = lRowRect(L, k);
    return float4(r.z - 44.0 * L.s, r.y + 4.0 * L.s, r.z - 6.0 * L.s, r.w - 4.0 * L.s);
}
int lRowAt(LLayout L, float2 px, out bool onSwitch)
{
    onSwitch = false;
    int hit = -1;
    [unroll] for (int k = 0; k < RACK_ROWS; k++)
    {
        if (hit < 0 && lInRect(px, lRowRect(L, k), 0.0)) { onSwitch = lInRect(px, lRowSwitch(L, k), 0.0); hit = k; }
    }
    return hit;
}
float4 lInfoRect(LLayout L)
{
    return float4(L.inspBody.x + 12.0 * L.s, L.inspBody.y + 8.0 * L.s, lRowRect(L, 0).x - 16.0 * L.s, L.inspBody.w - 10.0 * L.s);
}
float4 lChipRect(LLayout L, int k)
{
    float4 info = lInfoRect(L);
    float gap = 6.0 * L.s, h = ilSnap(30.0 * L.s);
    float w = (info.z - info.x - gap) * 0.5;
    int col = k % 2, row = k / 2;
    float x0 = info.x + (float)col * (w + gap);
    float y0 = info.w - 2.0 * h - gap + (float)row * (h + gap);
    return float4(x0, y0, x0 + w, y0 + h);
}
int lChipAt(LLayout L, float2 px)
{
    int hit = -1;
    [unroll] for (int k = 0; k < 4; k++) if (hit < 0 && lInRect(px, lChipRect(L, k), 0.0)) hit = k;
    return hit;
}

// ---- the plan's lights: the radius at which a light's floor illuminance falls to E, and the light
// a press at px takes (its dot selects it; its middle ring, LIGHT_RING_E, drags its power)
float lRingRadius(float P, float h, float E)
{
    // P h / (r^2 + h^2)^1.5 = E  ->  r^2 = (P h / E)^(2/3) - h^2
    float a = pow(max(P * h / max(E, 1e-5), 1e-6), 2.0 / 3.0) - h * h;
    return sqrt(max(a, 0.0));
}
int lLightAt(LLayout L, float2 px, float3 bulb[LIGHT_ROLES], float power[LIGHT_ROLES], bool ex[LIGHT_ROLES], out bool ring)
{
    int hit = -1;
    ring = false;
    float best = 14.0 * L.s;
    [unroll] for (int k = 0; k < LIGHT_ROLES; k++)
    {
        if (ex[k])
        {
            float dd = length(px - lPlanPx(L, bulb[k].xz));
            float rr = lRingRadius(power[k], max(bulb[k].y, 0.1), LIGHT_RING_E) * L.scale;
            if (dd < best) { best = dd; hit = k; ring = false; }
            if (abs(dd - rr) < 6.0 * L.s && abs(dd - rr) < best) { best = abs(dd - rr); hit = k; ring = true; }
        }
    }
    return hit;
}

#endif
