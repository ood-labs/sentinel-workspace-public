// Laser_Fixture / lf_view.hlsli - the Plan and Elevation canvas's geometry, from the live extent.
// One place for the rects and for the room -> canvas mapping: preview.hlsl draws through it and
// layout.hlsl captions, rules and hovers through it, so what you see and what you inspect cannot
// disagree. Plain maths; needs the module's parameters in scope (position_*, projector_*).
//
//   head   title, input and scanner model
//   plan   the room from above: +z right (away from the wall), +x up   } one z axis and one
//   elev   the room from the side: +z right, +y up                     } scale: a metre is the
//   side   the readout panes (FIXTURE, BEAMS)                          } same length everywhere
//   foot   the verb
//
// Room frame (Laser Previs's): metres, drywall face z = 0 facing +z, y up.
#ifndef LF_VIEW_HLSLI
#define LF_VIEW_HLSLI

struct LFLayout
{
    float  s;        // ui scale (type never below ~9 px)
    float4 head;
    float4 plan;     // the two plates
    float4 elev;
    float4 planD;    // their drawing areas
    float4 elevD;
    float4 side;     // the readout column (zero when the canvas is too narrow for it)
    float4 foot;
    float  k;        // px per metre: both drawings, both axes
    float  zLo;      // z at the drawings' left edge
    float  xMid;     // x at the plan drawing's middle
    float  yLo;      // y at the elevation drawing's bottom edge
};

float lfScale(float2 R) { return clamp(min(R.x / 640.0, R.y / 400.0), 0.86, 2.0); }

// What the drawings must hold: from just behind the wall face to just behind the fixture (z), the
// room's centre line and every aperture of the bank (x), the floor to above the fixture (y).
void lfSpan(out float2 zr, out float2 xr, out float2 yr)
{
    float lane = (float)((uint)clamp(projector_count, 1, 4) - 1u) * 0.5 * projector_spacing;
    zr = float2(-0.5, position_z + 0.9);
    xr = float2(min(-1.8, position_x - lane - 0.8), max(1.8, position_x + lane + 0.8));
    yr = float2(-0.3, max(3.0, position_y + 0.8));
}

LFLayout lfLayout(float2 R)
{
    LFLayout L;
    float s = lfScale(R);
    L.s = s;
    float pad = 10.0 * s, gap = 8.0 * s;
    L.head = float4(0.0, 0.0, R.x, 34.0 * s);
    L.foot = float4(0.0, R.y - 26.0 * s, R.x, R.y);
    float4 body = float4(pad, L.head.w, R.x - pad, L.foot.y);
    // the readouts stand at the right while the drawings keep 60 % of the width
    float sideW = clamp(0.3 * R.x, 176.0 * s, 240.0 * s);
    bool side = (body.z - body.x) - sideW - gap >= 0.6 * (body.z - body.x);
    L.side = side ? float4(body.z - sideW, body.y, body.z, body.w) : float4(0.0, 0.0, 0.0, 0.0);
    float4 area = body;
    if (side) area.z = L.side.x - gap;
    // the plates share the width; their heights follow the room, so a metre is one length in both
    float capH = 22.0 * s, inL = 24.0 * s, inR = 10.0 * s, inT = 6.0 * s, inB = 6.0 * s, ruler = 16.0 * s;
    float2 zr, xr, yr;
    lfSpan(zr, xr, yr);
    float xs = xr.y - xr.x, ys = yr.y - yr.x;
    float dw = max(area.z - area.x - inL - inR, 32.0 * s);
    float dh = max(area.w - area.y - gap - 2.0 * (capH + inT) - inB - ruler, 32.0 * s);
    float hp = dh * xs / (xs + ys);
    L.k = min(dw / (zr.y - zr.x), dh / (xs + ys));
    L.zLo = zr.x;
    L.xMid = 0.5 * (xr.x + xr.y);
    L.yLo = yr.x;
    L.plan = float4(area.x, area.y, area.z, area.y + capH + inT + hp + inB);
    L.elev = float4(area.x, L.plan.w + gap, area.z, max(area.w, L.plan.w + gap + capH + inT + ruler + 8.0 * s));
    L.planD = float4(area.x + inL, L.plan.y + capH + inT, area.z - inR, L.plan.w - inB);
    L.elevD = float4(area.x + inL, L.elev.y + capH + inT, area.z - inR, L.elev.w - ruler);
    return L;
}

// room (metres) -> canvas px, per drawing; the two share z
float  lfZPx(LFLayout L, float z) { return L.planD.x + (z - L.zLo) * L.k; }
float  lfZAt(LFLayout L, float px) { return L.zLo + (px - L.planD.x) / L.k; }
float2 lfPlanPx(LFLayout L, float3 w) { return float2(lfZPx(L, w.z), 0.5 * (L.planD.y + L.planD.w) - (w.x - L.xMid) * L.k); }
float2 lfElevPx(LFLayout L, float3 w) { return float2(lfZPx(L, w.z), L.elevD.w - (w.y - L.yLo) * L.k); }
float2 lfPx(LFLayout L, float3 w, bool elev) { return elev ? lfElevPx(L, w) : lfPlanPx(L, w); }

// How far a ray from o along d travels: to the wall face when it gets there within range, else to
// the range. A beam stops where it lands.
float lfReach(float3 o, float3 d, float range)
{
    float t = range;
    if (d.z < -1e-6) t = min(range, -o.z / d.z);
    return t;
}
bool lfLands(float3 o, float3 d, float range) { return d.z < -1e-6 && -o.z <= -d.z * range; }

// The readout panes: 0 FIXTURE (7 rows), 1 BEAMS (3 rows). A pane with no room comes back empty.
float4 lfPane(LFLayout L, uint k)
{
    float s = L.s;
    float h0 = (34.0 + 7.0 * 20.0) * s, h1 = (34.0 + 3.0 * 20.0) * s;
    float y0 = L.side.y + (k == 1u ? h0 + 8.0 * s : 0.0);
    float y1 = y0 + (k == 0u ? h0 : h1);
    bool fits = L.side.z > L.side.x && y1 <= L.side.w;
    return fits ? float4(L.side.x, y0, L.side.z, y1) : float4(0.0, 0.0, 0.0, 0.0);
}
// row r of a pane (below its header strip), as a mid-line y
float lfRowY(LFLayout L, float4 p, uint r) { return p.y + 30.0 * L.s + ((float)r + 0.5) * 20.0 * L.s; }

#endif
