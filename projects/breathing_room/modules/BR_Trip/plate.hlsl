// BR_Trip / plate.hlsl -- the per-pixel half of the canvas: everything that is a field over the
// room or a curve over time. The shared UI kit draws the anchors, chrome and type over it
// (ui.hlsl, from layout.hlsl's draw list).
//
// NET: floor in the middle, the walls folded out flat from their own edges, the ceiling hinged
// off the east wall. On it, live: the GEOMETRY each wall and the ceiling carries right now (the
// renderer's own pattern function, at the strength the renderer applies it), a 25 cm LATTICE read
// through the texture swim (exaggerated x6, so you see where surfaces breathe, twist, drip and
// stream), and the openings, pictures and furniture for orientation.
// SCOPE: the last half minute of every running anchor's pulse (the selected one in accent) and of
// the dose envelope, with the next few seconds ahead of the playhead.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
StructuredBuffer<BRRec> TripBuf : register(t0);
#define TRIP_REC(i) TripBuf[i]
#include "../_shared/br_shade.hlsli"
#include "../_shared/br_trip.hlsli"
#include "trip_layout.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }
BRRec fu(uint i) { BRRec r; r.head = _Data1[i].head; r.dims = _Data1[i].dims; r.look = _Data1[i].look; r.meta = _Data1[i].meta; return r; }

float sdRect2(float2 p, float2 lo, float2 hi)
{
    float2 c = (lo + hi) * 0.5, h = (hi - lo) * 0.5;
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
// a hairline of width w px at signed distance d (metres) on the net
float hair(float dMetres, float scale, float w) { return ilStroke(dMetres * scale, w); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint Wd, Ht;
    OutputUAV.GetDimensions(Wd, Ht);
    if (tid.x >= Wd || tid.y >= Ht) return;
    float2 P = float2(tid.xy) + 0.5;

    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    BRRoom R = brDefaultRoom();
    if (haveShell) R = brRoomFromRec(sh(0));
    bool haveFurn = _Data1_Count >= 30u && abs(_Data1[0].head.x - ROLE_FURN) < 0.5;
    TLayout L = tLayout(float2(Wd, Ht), R);
    float3 col = IL_FIELD;

    BRTrip T = tripHeader();
    BRRec ed = TripBuf[TRIP_EDITOR];
    BRRec dg = TripBuf[TRIP_DIAG];
    int sel = (int)round(ed.head.y);

    // =========================================================================================
    // NET (the kit draws the pane's edge, header, captions and anchors)
    float dNet = ilSdBox(P, L.netPane, IL_RADIUS * L.s);
    float dScope = ilSdBox(P, L.scopePane, IL_RADIUS * L.s);
    if (dNet < 1.0)
    {
        ilOver(col, IL_PANEL, ilFill(dNet));
        float2 XY = tNetXY(L, P);
        int host; float3 w, nn;
        if (tInRect(P, L.netR, 0.0) && tNetToWorld(L, XY, host, w, nn))
        {
            col = IL_RAISE;
            // the swim lattice: a 25 cm grid in surface coordinates, read through the swim (x6)
            float3 q = tripSwim(w, nn, T);
            float3 qx = w + (q - w) * 6.0;
            float2 uvq = tripSurfaceUV(qx, nn);
            float2 g = abs(frac(uvq / 0.25 + 0.5) - 0.5) * 0.25 * L.scale;
            ilOver(col, IL_GRID * 1.6, ilStroke(min(g.x, g.y), 0.9));
            // the geometry the walls and ceiling carry right now (the renderer's own pattern)
            if (host != TH_FLOOR)
            {
                float S = tripGeometryAt(w, T);
                float3 pat = tripPattern(tripSurfaceUV(q, nn), T.time, T.motif, 1.0 / L.scale, 1.0 / tripFreq(T), 1e3);
                ilOver(col, IL_MID * 1.15, pat.x * saturate(S * 1.8));
            }
            // what lives on each surface, for orientation
            if (host >= TH_WALL0 && host < TH_WALL0 + 4)
            {
                int wl = host - TH_WALL0;
                float along = brWallAlongX(wl) ? w.x : w.z;
                [loop] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++)
                {
                    if (haveShell)
                    {
                        BROpening o = brOpeningFromRec(sh(5 + (uint)oi));
                        if (o.active && o.wall == wl)
                        {
                            float2 lo = float2(o.a - o.width * 0.5, o.sill), hi = float2(o.a + o.width * 0.5, o.sill + o.height);
                            if (o.kind == OPEN_FIREPLACE) { lo = float2(o.a - o.width * 0.5, 0.0); hi = float2(o.a + o.width * 0.5, R.H); }
                            float dB = sdRect2(float2(along, w.y), lo, hi);
                            if (brOpenIsHole(o.kind)) ilOver(col, IL_PANEL, step(dB, 0.0) * 0.85);
                            ilOver(col, IL_RULE * 1.5, hair(abs(dB), L.scale, 1.0));
                            if (o.kind == OPEN_FIREPLACE)
                            {
                                float dF = sdRect2(float2(along, w.y), float2(o.a - o.cols * 0.5, 0.0), float2(o.a + o.cols * 0.5, o.rows));
                                ilOver(col, IL_PANEL, step(dF, 0.0) * 0.7);
                                ilOver(col, IL_RULE * 1.5, hair(abs(dF), L.scale, 1.0));
                                ilOver(col, IL_RULE * 1.5, hair(abs(w.y - o.height), L.scale, 1.0) * step(abs(along - o.a), o.width * 0.5 + 0.06));
                            }
                        }
                    }
                }
                // pictures and mirrors hung on this wall
                [loop] for (int fa = 17; fa <= 19; fa++)
                {
                    if (haveFurn)
                    {
                        BRRec f = fu((uint)fa);
                        if ((int)round(f.head.y) == FK_ART && (int)round(f.meta.w) == -2 - wl && ((int)round(f.meta.z) & FF_HIDDEN) == 0)
                        {
                            float fa0 = brWallAlongX(wl) ? f.dims.x : f.dims.y;
                            float dA = sdRect2(float2(along, w.y), float2(fa0 - f.look.x * 0.5, f.dims.w), float2(fa0 + f.look.x * 0.5, f.dims.w + f.look.y));
                            ilOver(col, IL_RULE * 1.3, hair(abs(dA), L.scale, 1.0));
                        }
                    }
                }
            }
            else if (host == TH_FLOOR && haveFurn)
            {
                [loop] for (int fs = 0; fs < 30; fs++)
                {
                    BRRec f = fu((uint)fs);
                    int fk = (int)round(f.head.y);
                    if (fk != FK_NONE && fkHosting(fk) != FH_WALL && fkHosting(fk) != FH_CEIL && ((int)round(f.meta.z) & FF_HIDDEN) == 0)
                    {
                        float yaw = f.dims.z;
                        float2 dd = w.xz - f.dims.xy;
                        float2 lq = float2(dot(dd, float2(cos(yaw), -sin(yaw))), dot(dd, float2(sin(yaw), cos(yaw))));
                        float sdp = sdRect2(lq, -f.look.xz * 0.5, f.look.xz * 0.5);
                        ilOver(col, IL_RULE * 1.4, hair(abs(sdp), L.scale, 0.9) * ((fk == FK_RUG) ? 0.6 : 1.0));
                        if (fk != FK_RUG) ilOver(col, IL_RULE * 0.45, step(sdp, 0.0) * 0.55);
                    }
                }
            }
            else if (host == TH_CEIL && haveFurn)
            {
                BRRec pd = fu(10u);
                if ((int)round(pd.head.y) == FK_PENDANT)
                    ilOver(col, IL_RULE * 1.6, hair(abs(length(w.xz - pd.dims.xy) - 0.08), L.scale, 1.0));
                // the crown's footprint
                float dc = sdRect2(w.xz, float2(R.x0 + R.crown, R.z0 + R.crown), float2(R.x1 - R.crown, R.z1 - R.crown));
                ilOver(col, IL_RULE, hair(abs(dc), L.scale, 0.8));
            }
            // panel frames (the folds)
            float4 pr = tPanel(L, host);
            ilOver(col, IL_RULE * 1.7, hair(abs(sdRect2(XY, pr.xy, pr.zw)), L.scale, 1.0));
        }
    }

    // =========================================================================================
    // SCOPE: every running anchor's pulse over the last half minute and the next few seconds
    else if (dScope < 1.0)
    {
        ilOver(col, IL_PANEL, ilFill(dScope));
        float4 sp = tScopePlot(L);
        if (tInRect(P, sp, 0.0))
        {
            col = IL_WELL;
            float tAt = T.time + lerp(-SCOPE_PAST, SCOPE_AHEAD, (P.x - sp.x) / (sp.z - sp.x));
            float pxPerS = (sp.z - sp.x) / (SCOPE_PAST + SCOPE_AHEAD);
            float yMid = (sp.y + sp.w) * 0.5, amp = (sp.w - sp.y) * 0.42;
            // ticks every 5 s on the trip clock, and the pulses' zero line
            float sec5 = abs(frac(tAt / 5.0 + 0.5) - 0.5) * 5.0 * pxPerS;
            ilOver(col, IL_GRID * 1.4, ilStroke(sec5, 0.8));
            ilOver(col, IL_GRID * 1.4, ilStroke(abs(P.y - yMid), 0.8));
            [loop] for (int i = 0; i < TRIP_ANCH_MAX; i++)
            {
                BRAnchor A = tripAnchor(i);
                if (A.on)
                {
                    float w0 = A.rate * 6.2831853;
                    float v = sin(tAt * w0 + A.phase) * A.strength;
                    float dv = cos(tAt * w0 + A.phase) * A.strength * w0 * amp / pxPerS;
                    float dy = abs(P.y - (yMid - v * amp)) / sqrt(1.0 + dv * dv);
                    bool isSel = i == sel;
                    ilOver(col, isSel ? IL_ACCENT : IL_MID * 0.8, ilStroke(dy, isSel ? 2.0 : 1.0) * (isSel ? 1.0 : 0.7));
                }
            }
            // the dose envelope (what the whole trip is scaled by)
            int arcK = (int)round(arc);
            float base = saturate(dg.meta.x);
            float e = tripEnvelope(arcK, max(tAt, 0.0)) * base;
            float e2 = tripEnvelope(arcK, max(tAt + 0.25, 0.0)) * base;
            float yE = sp.w - e * (sp.w - sp.y);
            float slope = (e2 - e) / (0.25 * pxPerS) * (sp.w - sp.y);
            ilOver(col, IL_INK, ilStroke(abs(P.y - yE) / sqrt(1.0 + slope * slope), 2.2));
        }
    }
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
