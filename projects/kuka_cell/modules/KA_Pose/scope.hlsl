// KA_Pose / scope.hlsl — the choreography instrument's DRAWING.
//
// Deliberately NOT a second plan. The plan answers "where does everything stand"; this answers
// "what is every joint doing right now, on whose clock, and is anything about to break".
//
// It is shaped like a teach pendant because that is what a draughtsman would draw for a machine
// organised by JOINTS AND TIME rather than by floor space: four channel stations across the top
// carrying the live phase of each clock, a joint matrix of one row per machine by six columns
// per axis, and a tool-height strip along the bottom with the floor drawn on it.
//
// The failure modes live in the diagram: a joint sitting on its limit turns its bar red, and a
// tool that has gone through the floor drops into a red band below the floor line. Neither is
// visible in the render until it has already happened.
//
// This pass draws the matrix and the tool strip on their plates. The stations (kit panes with live
// phase wheels), every caption, row number and readout, the hover card and the footer are recorded
// by layout.hlsl and drawn over this by the shared UI kit (ui.hlsl).
#include "../_shared/cell.hlsli"
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ka_ui.hlsli"
#include "pose_frame.hlsli"

StructuredBuffer<KaPose> Pose  : register(t0);
StructuredBuffer<KaRec>  Cell  : register(t1);
StructuredBuffer<KaBall> Rally : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

float strokeAA(float d, float w) { return 1.0 - smoothstep(w - 0.7, w + 0.7, d); }
float discAA(float2 p, float2 c, float r) { return 1.0 - smoothstep(r - 0.8, r + 0.8, length(p - c)); }
float boxFill(float2 p, float2 lo, float2 hi)
{
    return (p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y) ? 1.0 : 0.0;
}

float jointOf(KaPose p, uint c)
{
    if (c == 0u) return p.a1;
    if (c == 1u) return p.a2;
    if (c == 2u) return p.a3;
    if (c == 3u) return p.a4;
    if (c == 4u) return p.a5;
    return p.a6;
}
float homeOf(uint c)
{
    if (c == 0u) return KA_HOME_A1;
    if (c == 1u) return KA_HOME_A2;
    if (c == 2u) return KA_HOME_A3;
    if (c == 3u) return KA_HOME_A4;
    if (c == 4u) return KA_HOME_A5;
    return KA_HOME_A6;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pixel = DTid.xy;
    if (pixel.x >= W || pixel.y >= H) return;
    float2 P = (float2)pixel + 0.5;
    PoFrame F = poFrame(float2(W, H));
    float s = F.s;

    KaPose hdr = Pose[KA_HEADER];
    float liveN = hdr.elbow.y;
    float maxTool = hdr.a5;

    float3 outCol = IL_FIELD;

    // ================= joint matrix =================
    float dMat = ilSdBox(P, F.mat, IL_RADIUS * s);
    if (dMat < 1.0)
    {
        float3 col = IL_PANEL;
        float colW = F.colW;
        if (P.y >= F.rows.y && P.y <= F.rows.w)
        {
            // column separators
            for (uint c = 0u; c < 6u; c++)
                col = lerp(col, PT_RULE * 0.5, strokeAA(abs(P.x - (F.colX0 + (float)c * colW)), 0.5));

            float n = max(liveN, 1.0);
            float rowH = poRowH(F, liveN);
            int row = (int)floor((P.y - F.rows.y) / rowH);
            if (row >= 0 && (float)row < n)
            {
                // resolve the ordinal to a record index
                uint found = 0xFFFFFFFFu; uint ord = 0u;
                for (uint i = 0u; i < KA_MAX_ARMS; i++)
                {
                    if (Pose[KA_ARM_0 + i].live > 0.5)
                    {
                        if ((int)ord == row) { found = i; break; }
                        ord++;
                    }
                }
                if (found != 0xFFFFFFFFu)
                {
                    KaPose q = Pose[KA_ARM_0 + found];
                    KaRec  r = Cell[KA_ARM_0 + found];
                    bool isSel = ((uint)r.flags & KF_SELECTED) != 0u;
                    float ry = F.rows.y + (float)row * rowH;
                    float cy = ry + rowH * 0.5;
                    uint al = (uint)q.alarm;

                    // zebra the rows so a 48-row matrix stays trackable across 900 pixels
                    col = lerp(col, IL_WELL, ((row & 1) == 0) ? 0.6 : 0.0);
                    if (isSel) col = lerp(col, PT_ACCENT * 0.16, 1.0);
                    if ((al & KA_ALARM_FLOOR) != 0u) col = lerp(col, PT_ALARM * 0.22, 1.0);

                    // gutter: identity swatch. An arm that has been taken over by the rally is no
                    // longer running its channel pattern, so the matrix has to say so or the reader
                    // will look for a pattern that is not driving it.
                    float3 idc = ptId((int)q.chan);
                    KaBall rb = Rally[KA_ARM_0 + found];
                    if (rb.role == KA_ROLE_STRIKE || rb.role == KA_ROLE_RECEIVE) idc = PT_ACCENT;
                    else if (rb.role != KA_ROLE_NONE) idc = lerp(idc, PT_INK, 0.45);
                    float gx = F.mat.x + 8.0 * s;
                    col = lerp(col, idc, boxFill(P, float2(gx, cy - 3.0 * s), float2(gx + 6.0 * s, cy + 3.0 * s)));

                    // six joint bars
                    int cIdx = (int)floor((P.x - F.colX0) / colW);
                    if (cIdx >= 0 && cIdx < 6)
                    {
                        uint cu = (uint)cIdx;
                        float cx0 = F.colX0 + (float)cIdx * colW + 7.0 * s;
                        float cx1 = F.colX0 + (float)(cIdx + 1) * colW - 7.0 * s;
                        float2 lim = KA_LIM[cu];
                        float v = jointOf(q, cu);
                        float hm = homeOf(cu);
                        float tv = saturate((v - lim.x) / max(lim.y - lim.x, 1e-4));
                        float th = saturate((hm - lim.x) / max(lim.y - lim.x, 1e-4));
                        float xv = lerp(cx0, cx1, tv);
                        float xh = lerp(cx0, cx1, th);
                        float bh = max(rowH * 0.30, 1.6);

                        // At-limit is a per-joint fact, so it is tested per joint. A whole-arm flag
                        // would paint six bars red because one of them clipped.
                        bool atLim = ka_jointOnStop(v, cu);

                        col = lerp(col, PT_GRID * 1.7, strokeAA(abs(P.y - cy), 0.5) *
                                   ((P.x >= cx0 && P.x <= cx1) ? 1.0 : 0.0));
                        col = lerp(col, PT_RULE * 0.9, strokeAA(ilSdSeg(P, float2(cx0, cy - bh), float2(cx0, cy + bh)), 0.5));
                        col = lerp(col, PT_RULE * 0.9, strokeAA(ilSdSeg(P, float2(cx1, cy - bh), float2(cx1, cy + bh)), 0.5));
                        col = lerp(col, PT_RULE * 0.75, strokeAA(ilSdSeg(P, float2(xh, cy - bh * 0.7), float2(xh, cy + bh * 0.7)), 0.5));

                        float3 bc = atLim ? PT_ALARM : (isSel ? PT_ACCENT : PT_MID);
                        float bar = boxFill(P, float2(min(xh, xv), cy - bh), float2(max(xh, xv), cy + bh));
                        col = lerp(col, bc * 0.8, bar);
                        col = lerp(col, atLim ? PT_ALARM : PT_INK,
                                   strokeAA(ilSdSeg(P, float2(xv, cy - bh * 1.25), float2(xv, cy + bh * 1.25)), 0.8));
                    }
                }
            }
        }
        ilOver(outCol, col, ilFill(dMat));
    }

    // ================= tool height strip =================
    float dTool = ilSdBox(P, F.tool, IL_RADIUS * s);
    if (dTool < 1.0)
    {
        float3 col = IL_PANEL;
        // The floor sits above the plate's bottom so there is somewhere for a tool that has gone
        // THROUGH it to be drawn. A violation you cannot plot is a violation you find out about
        // from the render.
        float fy = F.plot.w;
        float top = F.plot.y;
        float ppm = poToolPpm(F, maxTool);
        bool inPlotX = P.x > F.plot.x && P.x < F.plot.z;

        col = lerp(col, PT_ALARM * 0.16, (P.y > fy && inPlotX) ? 1.0 : 0.0);
        for (uint k = 1u; k < 10u; k++)
        {
            float ty = fy - (float)k * ppm;
            if (ty < top) break;
            col = lerp(col, PT_GRID * 1.6, strokeAA(abs(P.y - ty), 0.5) * (inPlotX ? 1.0 : 0.0));
        }

        float n = max(liveN, 1.0);
        uint ord = 0u;
        for (uint i = 0u; i < KA_MAX_ARMS; i++)
        {
            KaPose q = Pose[KA_ARM_0 + i];
            if (q.live < 0.5) continue;
            float px = poStemX(F, ord, n);
            ord++;
            if (abs(P.x - px) > 5.0 * s) continue;
            float py = fy - q.tool.y * ppm;
            bool bad = ((uint)q.alarm & KA_ALARM_FLOOR) != 0u;
            float3 dc = bad ? PT_ALARM : ptId((int)q.chan);
            col = lerp(col, dc * 0.45, strokeAA(ilSdSeg(P, float2(px, fy), float2(px, py)), 0.5));
            col = lerp(col, dc, discAA(P, float2(px, py), bad ? 3.2 : 2.4));
        }

        // the target height, as the line the AIM channel is trying to reach
        {
            KaRec t = Cell[KA_TARGET];
            float ty = fy - ka_targetPos(t).y * ppm;
            if (ty > top)
                col = lerp(col, PT_INK * 0.85, strokeAA(abs(P.y - ty), 0.5) *
                           step(frac(P.x * 0.09), 0.5) * 0.9 * (inPlotX ? 1.0 : 0.0));
        }

        col = lerp(col, PT_RULE * 1.4, strokeAA(abs(P.y - fy), 0.9) * (inPlotX ? 1.0 : 0.0));
        ilOver(outCol, col, ilFill(dTool));
    }

    OutputUAV[pixel] = float4(outCol, 1.0);
}
