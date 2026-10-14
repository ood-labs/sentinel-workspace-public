// trip_layout.hlsli -- the ONE layout of BR_Trip's canvas, shared by the reducer (trip.hlsl), the
// per-pixel plate (plate.hlsl) and the draw list (layout.hlsl), so what you see is what you hit.
// Output pixels throughout, scaled by the Interaction Lab kit's ui scale (ilCtx).
//
// The room is drawn UNFOLDED, the way an interior designer develops a room: the floor plan in
// the middle, each wall folded out flat from its own edge of the floor (drawn as an elevation),
// and the ceiling hinged off the top of the east wall. Every fold is a shared edge, so an anchor
// dragged up the east wall carries straight on across the ceiling.
//
//   net coordinates (metres, Y down):
//                 +--------+
//                 | WALL N |
//      +----------+--------+----------+-----------+
//      | WALL W   | FLOOR  | WALL E   |  CEILING  |   (ceiling: mirror of the plan,
//      +----------+--------+----------+-----------+    hinged on the east wall's top)
//                 | WALL S |
//                 +--------+
#ifndef TRIP_LAYOUT_HLSLI
#define TRIP_LAYOUT_HLSLI

#include "../_shared/ui/il_core.hlsli"

struct TLayout
{
    float2 res;
    float s;              // ui scale (1 at 1280 x 720)
    float4 head;          // the title strip
    float4 netPane, netR;       // the unfolded room's pane, and its body
    float4 scopePane, scopeR;   // the scope's pane, and its body
    float4 sidePane, sideR;     // the inspector's pane, and its body
    float scale;          // px per metre on the net
    float2 o;             // pixel of net (0, 0)
    float W, D, H;        // room width (x), depth (z), height
    float x0, x1, z0, z1;
};

TLayout tLayout(float2 res, BRRoom r)
{
    TLayout L;
    L.res = res;
    L.s = ilCtx(res).s;
    float m = ilSnap(10.0 * L.s), hh = ilSnap(IL_HEADER * L.s);
    L.head = float4(0.0, 0.0, res.x, ilSnap(36.0 * L.s));
    float4 body = float4(m, L.head.w, res.x - m, res.y - m);
    L.sidePane = ilCutRight(body, ilSnap(300.0 * L.s));
    body.z -= m;
    L.scopePane = ilCutBottom(body, ilSnap(150.0 * L.s));
    body.w -= m;
    L.netPane = body;
    L.netR = L.netPane;   ilCutTop(L.netR, hh);
    L.scopeR = L.scopePane; ilCutTop(L.scopeR, hh);
    L.sideR = L.sidePane; ilCutTop(L.sideR, hh);
    L.x0 = r.x0; L.x1 = r.x1; L.z0 = r.z0; L.z1 = r.z1;
    L.W = r.x1 - r.x0; L.D = r.z1 - r.z0; L.H = r.H;
    float netW = 2.0 * L.H + 2.0 * L.W, netH = 2.0 * L.H + L.D;
    float pad = 14.0 * L.s;
    float2 avail = float2(L.netR.z - L.netR.x - 2.0 * pad, L.netR.w - L.netR.y - 2.0 * pad);
    L.scale = max(min(avail.x / netW, avail.y / netH), 1.0);
    float2 c = ilMid(L.netR);
    L.o = c - float2(netW, netH) * 0.5 * L.scale;
    return L;
}

bool tInRect(float2 p, float4 r, float pad) { return p.x >= r.x - pad && p.x <= r.z + pad && p.y >= r.y - pad && p.y <= r.w + pad; }
float2 tNetPx(TLayout L, float2 XY) { return L.o + XY * L.scale; }
float2 tNetXY(TLayout L, float2 px) { return (px - L.o) / L.scale; }

// Net rectangle (metres) of each surface.
float4 tPanel(TLayout L, int host)
{
    float H = L.H, W = L.W, D = L.D;
    if (host == TH_FLOOR) return float4(H, H, H + W, H + D);
    if (host == TH_CEIL)  return float4(2.0 * H + W, H, 2.0 * H + 2.0 * W, H + D);
    if (host == TH_WALL0 + WALL_N) return float4(H, 0.0, H + W, H);
    if (host == TH_WALL0 + WALL_S) return float4(H, H + D, H + W, 2.0 * H + D);
    if (host == TH_WALL0 + WALL_W) return float4(0.0, H, H, H + D);
    return float4(H + W, H, 2.0 * H + W, H + D);                 // WALL_E
}

// World point on a host surface -> net XY.
float2 tWorldToNet(TLayout L, int host, float3 p)
{
    float H = L.H, W = L.W, D = L.D;
    float X = H + (p.x - L.x0), Y = H + (L.z1 - p.z);
    if (host == TH_FLOOR) return float2(X, Y);
    if (host == TH_CEIL) return float2(2.0 * H + W + (L.x1 - p.x), Y);
    if (host == TH_WALL0 + WALL_N) return float2(X, H - p.y);
    if (host == TH_WALL0 + WALL_S) return float2(X, H + D + p.y);
    if (host == TH_WALL0 + WALL_W) return float2(H - p.y, Y);
    return float2(H + W + p.y, Y);                               // WALL_E
}

// Net XY -> the surface it lies on, the world point there and the surface's inward normal.
// False in the empty corners of the cross.
bool tNetToWorld(TLayout L, float2 XY, out int host, out float3 p, out float3 n)
{
    float H = L.H, W = L.W, D = L.D;
    host = -1; p = 0; n = float3(0, 1, 0);
    float x = L.x0 + (XY.x - H), z = L.z1 - (XY.y - H);
    if (XY.y >= H && XY.y <= H + D)
    {
        if (XY.x >= H && XY.x <= H + W) { host = TH_FLOOR; p = float3(x, 0.0, z); n = float3(0, 1, 0); return true; }
        if (XY.x >= 0.0 && XY.x < H) { host = TH_WALL0 + WALL_W; p = float3(L.x0, H - XY.x, z); n = float3(1, 0, 0); return true; }
        if (XY.x > H + W && XY.x <= 2.0 * H + W) { host = TH_WALL0 + WALL_E; p = float3(L.x1, XY.x - (H + W), z); n = float3(-1, 0, 0); return true; }
        if (XY.x > 2.0 * H + W && XY.x <= 2.0 * H + 2.0 * W) { host = TH_CEIL; p = float3(L.x1 - (XY.x - (2.0 * H + W)), H, z); n = float3(0, -1, 0); return true; }
        return false;
    }
    if (XY.x >= H && XY.x <= H + W)
    {
        if (XY.y >= 0.0 && XY.y < H) { host = TH_WALL0 + WALL_N; p = float3(x, H - XY.y, L.z1); n = float3(0, 0, -1); return true; }
        if (XY.y > H + D && XY.y <= 2.0 * H + D) { host = TH_WALL0 + WALL_S; p = float3(x, XY.y - (H + D), L.z0); n = float3(0, 0, 1); return true; }
    }
    return false;
}

// An anchor's pixel on the net (an anchor on a piece of furniture sits on the floor plan).
float2 tAnchorPx(TLayout L, BRAnchor A) { return tNetPx(L, tWorldToNet(L, (A.host >= TH_OBJ0) ? TH_FLOOR : A.host, A.c)); }

// The pick a press runs, one candidate at a time: the nearest centre within TRIP_GRAB moves the
// anchor, a reach ring within TRIP_RING_GRAB resizes it. The layout's hover asks the same.
#define TRIP_GRAB      14.0    // ui px from an anchor's centre
#define TRIP_RING_GRAB 6.0     // ui px either side of its reach ring
void tPickTest(TLayout L, float2 px, float2 ap, float rr, int k, inout float best, inout int hit, inout bool ring)
{
    float dd = length(px - ap);
    if (dd < best) { best = dd; hit = k; ring = false; }
    if (abs(dd - rr) < TRIP_RING_GRAB * L.s && abs(dd - rr) < best) { best = abs(dd - rr); hit = k; ring = true; }
}

// ---- the inspector's pane: rows from the top, chips at the bottom (2 columns x 4 rows)
#define TRIP_ROW_H 22.0
float4 tRowRect(TLayout L, float k)
{
    float pad = 12.0 * L.s, rh = ilSnap(TRIP_ROW_H * L.s);
    float y0 = L.sideR.y + 6.0 * L.s + k * rh;
    return float4(L.sideR.x + pad, y0, L.sideR.z - pad, y0 + rh);
}
#define TRIP_CHIPS 8
float4 tChipRect(TLayout L, int k)
{
    float gap = 6.0 * L.s, h = ilSnap(32.0 * L.s), pad = 12.0 * L.s;
    float w = (L.sideR.z - L.sideR.x - 2.0 * pad - gap) * 0.5;
    int col = k % 2, row = k / 2;
    float x0 = L.sideR.x + pad + (float)col * (w + gap);
    float y0 = L.sideR.w - pad - 4.0 * h - 3.0 * gap + (float)row * (h + gap);
    return float4(x0, y0, x0 + w, y0 + h);
}
int tChipAt(TLayout L, float2 px)
{
    int hit = -1;
    [unroll] for (int k = 0; k < TRIP_CHIPS; k++) if (hit < 0 && tInRect(px, tChipRect(L, k), 0.0)) hit = k;
    return hit;
}

// ---- the scope: trip seconds [now - SCOPE_PAST, now + SCOPE_AHEAD] across
#define SCOPE_PAST  24.0
#define SCOPE_AHEAD 6.0
float4 tScopePlot(TLayout L)
{
    float padL = 34.0 * L.s, padR = 34.0 * L.s, padT = 10.0 * L.s, padB = 22.0 * L.s;
    return float4(L.scopeR.x + padL, L.scopeR.y + padT, L.scopeR.z - padR, L.scopeR.w - padB);
}
float tScopeX(TLayout L, float dtFromNow)
{
    float4 p = tScopePlot(L);
    return lerp(p.x, p.z, (dtFromNow + SCOPE_PAST) / (SCOPE_PAST + SCOPE_AHEAD));
}

#endif
