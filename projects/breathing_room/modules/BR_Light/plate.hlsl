// BR_Light / plate.hlsl -- the per-pixel drawings under BR_Light's chrome: the content background
// the shared UI kit draws the paths, handles, rings and type over (ui.hlsl, from layout.hlsl).
//
// SUN PATH: the sky seen from the middle of the room, azimuth across (N E S W N), elevation up,
// with the street-tree canopy (the same density field the renderer uses), the skyline and the
// window openings mapped onto it -- the only sky the sun can reach the room through.
// PLAN: the room, the furniture faint, the walls cut at their openings, and the patches the sun
// paints on the floor through each window (the same light tunnel the renderer's GI uses), in the
// sun's own colour through ptSampleFill.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#include "../_shared/br_light_defs.hlsli"
#include "../_shared/br_shade.hlsli"          // brVN3, which br_sky needs
#include "../_shared/br_sky.hlsli"
#include "light_layout.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<BRRec> LightBuf : register(t0);

BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }
BRRec fu(uint i) { BRRec r; r.head = _Data1[i].head; r.dims = _Data1[i].dims; r.look = _Data1[i].look; r.meta = _Data1[i].meta; return r; }

// a line of width w px at distance d px
float stroke(float d, float w) { return ilStroke(d, w); }
// section hatch: parallel lines at `angle`, `spacing` px apart, `w` px wide
float hatch(float2 P, float spacing, float angle, float w)
{
    float2 dir = float2(cos(angle), sin(angle));
    float t = dot(P, float2(-dir.y, dir.x));
    return stroke(abs(frac(t / spacing + 0.5) - 0.5) * spacing, w);
}
float sdRect2(float2 p, float2 lo, float2 hi)
{
    float2 c = (lo + hi) * 0.5, h = (hi - lo) * 0.5;
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, Hh;
    OutputUAV.GetDimensions(W, Hh);
    if (tid.x >= W || tid.y >= Hh) return;
    float2 res = float2(W, Hh);
    float2 P = float2(tid.xy) + 0.5;

    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    BRRoom r = brDefaultRoom();
    if (haveShell) r = brRoomFromRec(sh(0));
    bool haveFurn = _Data1_Count >= 30u;
    LLayout L = lLayout(res, r);
    float3 col = IL_FIELD;

    BRRec sun = LightBuf[LIGHT_SUN];
    float3 sd = normalize(sun.dims.xyz + 1e-6);
    float compassDeg = sun.meta.w;
    float3 sunCol = brSunColour(sd);
    float3 sunN = sunCol / max(max(sunCol.r, max(sunCol.g, sunCol.b)), 1e-4);
    float3 eye = float3((r.x0 + r.x1) * 0.5, 1.1, (r.z0 + r.z1) * 0.5);

    // =========================================================================================
    // SUN PATH: the pane's card, the sky, the canopy, the skyline and the windows
    float dc = ilSdBox(P, L.chartR, IL_RADIUS * L.s);
    if (dc < 1.0)
    {
        ilOver(col, IL_PANEL, ilFill(dc));
        float4 pl = lChartPlot(L);
        if (lInRect(P, pl, 0.0))
        {
            float2 ae = lChartAzEl(L, P);
            float az = ae.x, el = ae.y;
            float azW = az - radians(compassDeg);
            float3 dir = float3(sin(azW) * cos(el), sin(el), cos(azW) * cos(el));
            // the sky, a little lighter toward the horizon
            col = lerp(IL_WELL * 2.4, IL_WELL * 1.2, saturate(el / 1.2));
            // street-tree canopy as seen from the room
            BRSkyCtx S;
            S.sunDir = sd; S.sunRad = 0; S.sunI = 1; S.time = 0; S.wind = 0; S.canopy = sun.look.w;
            S.building = float4(r.x0 - r.T, r.x1 + r.T, r.z0 - r.T, r.z1 + r.T);
            // leave the building first
            float3 inv = 1.0 / (abs(dir) > 1e-5 ? dir : float3(1e-5, 1e-5, 1e-5));
            float3 lo = float3(S.building.x, -3.0, S.building.z) - eye, hi = float3(S.building.y, 9.0, S.building.w) - eye;
            float3 t0 = lo * inv, t1 = hi * inv;
            float tExit = min(min(max(t0.x, t1.x), max(t0.y, t1.y)), max(t0.z, t1.z));
            float Tc = brCanopyTransmit(eye + dir * max(tExit, 0.0), dir, S, 0.0);
            ilOver(col, IL_RULE * 0.9, (1.0 - Tc) * 0.85);
            ilOver(col, IL_RULE * 1.6, (1.0 - Tc) * hatch(P, 4.0 * L.s, -0.785, 0.8) * 0.8);
            // skyline: the far roofs (the formula brExterior draws them with)
            float bldg = floor(azW * 9.0);
            float hb = frac(sin(bldg * 91.7) * 4375.85);
            float roofEl = 0.020 + hb * 0.055 + step(0.85, hb) * 0.05;
            ilOver(col, IL_RULE * 0.7, step(el, roofEl));
            // grid: every 45 degrees of azimuth, every 10 of elevation
            float2 g = float2(az / 0.7853982, el / 0.1745329);
            float2 gd = abs(frac(g + 0.5) - 0.5) * float2((pl.z - pl.x) / 8.0, (pl.w - pl.y) / 8.0);
            ilOver(col, IL_GRID * 1.5, stroke(min(gd.x, gd.y), 0.8));
        }
        // window apertures from the middle of the room
        if (lInRect(P, L.chartBody, 0.0))
        {
            [loop] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++)
            {
                if (!haveShell) break;
                BROpening o = brOpeningFromRec(sh(5 + (uint)oi));
                if (!o.active || !(brOpenIsGlazed(o.kind) || o.kind == OPEN_ARCH)) continue;
                float hw = o.width * 0.5;
                float2 c0 = brWallPoint(r, o.wall, o.a - hw, 0.0), c1 = brWallPoint(r, o.wall, o.a + hw, 0.0);
                float2 q[4];
                q[0] = dirAzEl(normalize(float3(c0.x, o.sill, c0.y) - eye), compassDeg);
                q[1] = dirAzEl(normalize(float3(c1.x, o.sill, c1.y) - eye), compassDeg);
                q[2] = dirAzEl(normalize(float3(c1.x, o.sill + o.height, c1.y) - eye), compassDeg);
                q[3] = dirAzEl(normalize(float3(c0.x, o.sill + o.height, c0.y) - eye), compassDeg);
                float2 Q[4];
                [unroll] for (int k = 0; k < 4; k++) Q[k] = lChartPx(L, q[k].x, max(q[k].y, -0.05));
                // inside test (convex quad) and outline
                float sgn = 0.0, inside = 1.0, edge = 1e9;
                [unroll] for (int k2 = 0; k2 < 4; k2++)
                {
                    float2 a = Q[k2], b = Q[(k2 + 1) % 4];
                    float cr = (b.x - a.x) * (P.y - a.y) - (b.y - a.y) * (P.x - a.x);
                    if (k2 == 0) sgn = sign(cr);
                    if (sign(cr) != sgn) inside = 0.0;
                    edge = min(edge, ilSdSeg(P, a, b));
                }
                ilOver(col, PT_ID_A * 0.35, inside * 0.55);
                ilOver(col, IL_MID, stroke(edge, 1.2));
            }
        }
    }

    // =========================================================================================
    // PLAN: the room, the sun patches, the furniture, the walls
    float dp = ilSdBox(P, L.planR, IL_RADIUS * L.s);
    if (dp < 1.0)
    {
        ilOver(col, IL_PANEL, ilFill(dp));
        if (lInRect(P, L.planBody, 0.0))
        {
            float sc = L.scale;
            float2 wp = lPlanWorld(L, P);
            bool inRoom = wp.x >= r.x0 && wp.x <= r.x1 && wp.y >= r.z0 && wp.y <= r.z1;
            col = inRoom ? IL_RAISE * 0.75 : IL_WELL;          // the room's floor reads as the sheet
            // sun patches on the floor (the light tunnel through each window)
            float patch = 0.0, patchEdge = 1e9;
            [loop] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++)
            {
                if (!haveShell) break;
                BROpening o = brOpeningFromRec(sh(5 + (uint)oi));
                if (!o.active || !brOpenIsGlazed(o.kind)) continue;
                float2 n2 = brWallNormal(o.wall);
                float2 al = brWallAlongX(o.wall) ? float2(1, 0) : float2(0, 1);
                float2 p0 = brWallPoint(r, o.wall, 0.0, 0.0);
                float3 Q0, E1, E2;
                if (!brSunPatch(p0, n2, al, o.a, o.width, o.sill, o.height, r.T, sd, Q0, E1, E2)) continue;
                float det = E1.x * E2.z - E1.z * E2.x;
                if (abs(det) < 1e-6) continue;
                float2 d = wp - Q0.xz;
                float u = (d.x * E2.z - d.y * E2.x) / det;
                float v = (E1.x * d.y - E1.z * d.x) / det;
                if (u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0 && inRoom) patch = 1.0;
                float2 a = Q0.xz, b = (Q0 + E1).xz, c = (Q0 + E1 + E2).xz, e = (Q0 + E2).xz;
                patchEdge = min(patchEdge, min(min(ilSdSeg(wp, a, b), ilSdSeg(wp, b, c)), min(ilSdSeg(wp, c, e), ilSdSeg(wp, e, a))));
            }
            ilOver(col, ptSampleFill(sunN) * 1.4, patch * 0.75);
            ilOver(col, ptSampleColour(sunN) * 0.9, stroke(patchEdge * sc, 1.0) * (inRoom ? 1.0 : 0.0));
            // furniture, faint
            if (haveFurn)
            {
                [loop] for (int s = 0; s < 30; s++)
                {
                    BRRec f = fu((uint)s);
                    int kind = (int)round(f.head.y), flags = (int)round(f.meta.z);
                    if (kind == FK_NONE || (flags & FF_HIDDEN) != 0 || kind == FK_ART) continue;
                    float yaw = f.dims.z;
                    float2 dd = wp - f.dims.xy;
                    float2 l = float2(dot(dd, float2(cos(yaw), -sin(yaw))), dot(dd, float2(sin(yaw), cos(yaw))));
                    float2 h = f.look.xz * 0.5;
                    float sdp = sdRect2(l, -h, h);
                    ilOver(col, IL_RULE * 1.3, stroke(abs(sdp) * sc, 0.9) * ((kind == FK_RUG) ? 0.6 : 1.0));
                    if (kind != FK_RUG) ilOver(col, IL_RULE * 0.45, step(sdp, 0.0) * 0.6);
                }
            }
            // walls, cut through at their openings
            float T = r.T;
            float dIn = abs(sdRect2(wp, float2(r.x0, r.z0), float2(r.x1, r.z1)));
            float dOut = abs(sdRect2(wp, float2(r.x0 - T, r.z0 - T), float2(r.x1 + T, r.z1 + T)));
            bool band = !inRoom && wp.x >= r.x0 - T && wp.x <= r.x1 + T && wp.y >= r.z0 - T && wp.y <= r.z1 + T;
            float cut = 0.0;
            [loop] for (int oj = 0; oj < SHELL_OPEN_MAX; oj++)
            {
                if (!haveShell) break;
                BROpening o = brOpeningFromRec(sh(5 + (uint)oj));
                if (!o.active || !brOpenIsHole(o.kind)) continue;
                float along = brWallAlongX(o.wall) ? wp.x : wp.y;
                float2 n = brWallNormal(o.wall);
                float plane = brWallPlane(r, o.wall);
                float dd = brWallAlongX(o.wall) ? (wp.y - plane) * n.y : (wp.x - plane) * n.x;
                if (abs(along - o.a) <= o.width * 0.5 && dd <= 0.0 && dd >= -T) cut = 1.0;
            }
            if (band && cut < 0.5) ilOver(col, IL_RULE * 0.8, 1.0);
            ilOver(col, IL_MID, stroke(dIn * sc, 1.2) * (1.0 - cut));
            ilOver(col, IL_RULE * 1.4, stroke(dOut * sc, 1.0) * (1.0 - cut));
        }
    }
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
