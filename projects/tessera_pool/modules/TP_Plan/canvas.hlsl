// TP_Plan / canvas.hlsl — the editor's drawing: plan over section, sharing one x axis.
//
// This is an INSTRUMENT, not a small copy of the render. It is drawn from the shared instrument
// palette and stays near-monochrome: hue appears only for the selection accent, for the alarm
// state, and on the six palette chips, where the colour a record stores IS the information.
//
// The section strip earns its place three times over. It carries the water depth and the
// freeboard, which the plan cannot show at all; it carries the MEASURED wave envelope fed back
// from TP_Sim's control output, so the number on screen is live state and not a prediction; and
// it carries the failure mode — an envelope that clears the glass rim, or one that scrapes the
// floor — drawn in alarm red where it happens, so a broken arrangement is visible here instead
// of being discovered later as water spilling through the side of the tank.
#include "../_shared/tessera.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/microfont.hlsli"
#include "layout.hlsli"

StructuredBuffer<TpRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// ---------------------------------------------------------------------------
// Pixel-space primitives. Everything below works in pixels, so every stroke is a real stroke
// width and nothing thins out when the canvas is resized.
// ---------------------------------------------------------------------------
float aa(float d) { return saturate(0.5 - d); }                       // d in pixels, 1px feather

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}
float sdBox(float2 p, float2 c, float2 h)
{
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
float cvSeg(float2 p, float2 a, float2 b, float w) { return aa(sdSeg(p, a, b) - w * 0.5); }
float cvRing(float2 p, float2 c, float r, float w) { return aa(abs(length(p - c) - r) - w * 0.5); }
float cvDisc(float2 p, float2 c, float r)          { return aa(length(p - c) - r); }
float cvBoxLine(float2 p, float2 c, float2 h, float w) { return aa(abs(sdBox(p, c, h)) - w * 0.5); }
float cvBoxFill(float2 p, float2 c, float2 h)      { return aa(sdBox(p, c, h)); }

// dashed segment, dash length and gap in pixels
float cvDash(float2 p, float2 a, float2 b, float w, float dash)
{
    float2 ba = b - a;
    float L = length(ba);
    if (L < 1e-4) return 0.0;
    float t = saturate(dot(p - a, ba) / (L * L)) * L;
    float phase = frac(t / max(dash * 2.0, 1.0));
    return cvSeg(p, a, b, w) * step(phase, 0.5);
}

void ink(inout float3 dst, float3 col, float cov) { dst = lerp(dst, col, saturate(cov)); }

// ---------------------------------------------------------------------------
// Type. Fixed-point readouts, because a plan that rounds its own numbers to integers is
// useless for exactly the quantities this one exists to compare.
// ---------------------------------------------------------------------------
float mfFix(float2 p, float value, uint id, uint dd)
{
    uint cells = id + 1u + dd;
    if (p.y < 0.0 || p.y >= 1.0) return 0.0;
    float fx = p.x * (float)cells;
    if (fx < 0.0 || fx >= (float)cells) return 0.0;
    uint idx = (uint)fx;
    float2 lp = float2(frac(fx) * 1.2, p.y);
    if (idx == id) return mf_glyph(lp, MF_DOT);

    uint sc = 1u;
    for (uint k = 0u; k < dd; k++) sc *= 10u;
    uint total = (uint)round(clamp(value, 0.0, 999.0) * (float)sc);

    uint place = (idx < id) ? ((id - 1u - idx) + dd) : (dd - 1u - (idx - id - 1u));
    uint div = 1u;
    for (uint m = 0u; m < place; m++) div *= 10u;
    return mf_glyph(lp, (total / div) % 10u);
}

// string cell metrics: a glyph cell is 0.62 * height wide
float2 cellSpace(float2 px, float2 org, float h, uint cells)
{
    return (px - org) / float2(h * 0.62 * (float)cells, h);
}
float drawStr(float2 px, float2 org, float h, uint2 packed, uint count)
{
    return mf_text(cellSpace(px, org, h, count), packed, count);
}
float drawNum(float2 px, float2 org, float h, uint v, uint digits)
{
    return mf_num(cellSpace(px, org, h, digits), v, digits);
}
float drawFix(float2 px, float2 org, float h, float v, uint id, uint dd)
{
    return mfFix(cellSpace(px, org, h, id + 1u + dd), v, id, dd);
}
float drawGlyph(float2 px, float2 org, float h, uint g)
{
    return mf_glyph((px - org) / float2(h * 0.62, h), g);
}
float strW(float h, uint cells) { return h * 0.62 * (float)cells; }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (DTid.x >= W || DTid.y >= H) return;

    float2 res = float2(W, H);
    float2 px = float2(DTid.xy) + 0.5;

    TpRec hdr  = Plan[TP_HEADER];
    TpRec tank = Plan[TP_TANK];
    TpRec lamp = Plan[TP_LIGHT];
    TpLayout L = tpLayout(res, tank);

    float3 half3 = tpTankHalf(tank);
    float  thick = tpTankThick(tank);
    float  fb    = tpTankFree(tank);
    float  pitch = max(tpTankPitch(tank), 0.005);

    uint  sel     = (uint)hdr.pos.y;
    float liveN   = hdr.tint.y;

    // Live state, fed back from TP_Sim through a control-output expression. If the driver is
    // not wired this reads 0 and the envelope collapses to the waterline, which is honest:
    // the plan is then saying it has no measurement, not inventing one.
    float peak = max(sim_peak, 0.0);
    bool overRim = peak > fb;
    bool onFloor = peak > half3.y * 0.92;

    float3 c = PT_FIELD;

    // ======================================================================
    // PLAN STRIP — world (x, z) from above, viewer at the bottom edge
    // ======================================================================
    {
        float2 o = L.planC;
        float2 hIn = float2(half3.x, half3.z) * L.scale;
        float2 hOut = (float2(half3.x, half3.z) + thick) * L.scale;

        // well
        ink(c, PT_WELL, cvBoxFill(px, o, hOut));

        // tile grid at the REAL pitch, from the shared tile function's geometry. Grey: this is
        // chrome telling you the lining's scale and pattern, not a preview of its colour.
        {
            float2 q = (px - o) / L.scale;
            float inside = cvBoxFill(px, o, hIn);
            if (inside > 0.001)
            {
                int pat = (int)tank.pos.x;
                float2 cell = q / pitch;
                if (pat == 1) cell.x *= 0.5;
                if (pat == 1 || pat == 2)
                    cell.x += (fmod(floor(cell.y) + 64.0, 2.0) < 0.5) ? 0.0 : 0.5;
                float2 g = abs(frac(cell) - 0.5);
                float lw = 0.5 / (pitch * L.scale);
                float grid = max(smoothstep(0.5 - lw, 0.5, g.x), smoothstep(0.5 - lw, 0.5, g.y));
                if (pat == 2)
                {
                    float d = length(frac(cell) - 0.5) * 2.0;
                    grid = smoothstep(0.86, 0.86 + lw * 2.0, d) * (1.0 - smoothstep(1.0, 1.0 + lw * 2.0, d));
                }
                ink(c, PT_GRID, grid * inside * 0.85);
            }
        }

        // glass shell and interior
        ink(c, PT_RULE, cvBoxLine(px, o, hOut, 1.0));
        ink(c, PT_DIM,  cvBoxLine(px, o, hIn, 1.4));

        // centre crosshairs, quarter ticks
        ink(c, PT_GRID, cvSeg(px, o - float2(hIn.x, 0), o + float2(hIn.x, 0), 1.0));
        ink(c, PT_GRID, cvSeg(px, o - float2(0, hIn.y), o + float2(0, hIn.y), 1.0));

        // sun azimuth compass, clear of the box on its upper left. The arrow is the direction
        // the sun comes FROM, so it is also the direction every caustic slides away from.
        {
            float2 cc = float2(o.x - hOut.x - 26.0, o.y - hOut.y - 4.0);
            float2 d = normalize(float2(lamp.pos.x, lamp.pos.z) + 1e-5) * 12.0;
            ink(c, PT_RULE, cvRing(px, cc, 12.0, 1.0));
            ink(c, PT_DIM,  cvSeg(px, cc - d, cc + d, 1.3));
            ink(c, PT_DIM,  cvDisc(px, cc + d, 2.6));
        }

        // Everything a source draws is CLIPPED TO THE WATER. A ripple cannot exist outside the
        // tank, and an unclipped ring train reading straight through the glass wall is a
        // diagram telling a lie about what the sim will do with it.
        float water = cvBoxFill(px, o, hIn);

        for (uint i = 0u; i < TP_SRCS; i++)
        {
            TpRec r = Plan[TP_SRC_0 + i];
            bool isSel = (sel > 0u) && ((sel - 1u) == (TP_SRC_0 + i));
            bool edited = ((uint)r.flags & F_EDITED) != 0u;
            bool live = r.active > 0.5;

            float2 w = tpFootToWorld(float2(r.pos.x, r.pos.z), tank);
            float2 sp = tpPlanToPx(L, w);
            bool outside = (abs(r.pos.x) > 1.0 || abs(r.pos.z) > 1.0);

            float3 col = live ? (isSel ? PT_ACCENT : PT_MID) : PT_RULE;
            if (live && outside) col = PT_ALARM;               // a source outside the tank does nothing

            float rad = max(r.dims.x, 0.02) * half3.x * L.scale;

            if (!live)
            {
                // a switched-off source keeps its place and nothing else: a spare in the rack,
                // not a second ring train competing with the live ones
                ink(c, PT_RULE, cvRing(px, sp, max(rad, 3.5), 1.0) * water * 0.8);
                if (isSel) ink(c, PT_ACCENT, cvRing(px, sp, max(rad, 3.5) + 6.0, 1.0) * 0.7);
            }
            else if (r.kind == KIND_SWELL)
            {
                // a swell is a direction, not a point: draw the wavefront and the travel arrow
                float a = r.p3;
                float2 dir = float2(cos(a), sin(a));
                float2 perp = float2(-dir.y, dir.x);
                float len = 30.0 + 40.0 * saturate(r.p0);
                for (int k = 0; k < 3; k++)
                {
                    float off = (float)k * max(r.p2, 0.05) * L.scale * 0.55;
                    float2 b = sp + dir * off;
                    ink(c, col, cvSeg(px, b - perp * len, b + perp * len, isSel ? 2.0 : 1.3)
                                * water * (1.0 - 0.24 * (float)k));
                }
                ink(c, col, cvSeg(px, sp, sp + dir * len * 0.9, isSel ? 2.0 : 1.3) * water);
                ink(c, col, cvDisc(px, sp + dir * len * 0.9, isSel ? 3.4 : 2.6) * water);
            }
            else
            {
                // ring train: four rings spaced at the source's own wavelength, so the plan
                // shows the SCALE of the pattern it will make and not just where it sits
                for (int k = 1; k <= 4; k++)
                {
                    float rr = rad + (float)k * max(r.p2, 0.03) * L.scale;
                    ink(c, col, cvRing(px, sp, rr, isSel ? 1.6 : 1.0) * water * (1.0 - 0.19 * (float)k));
                }
                ink(c, col, cvDisc(px, sp, max(rad, 3.0)) * water);

                // an emitter is marked by a second, tighter ring: it never stops
                if (r.kind == KIND_EMIT)
                    ink(c, col, cvRing(px, sp, max(rad, 3.0) + 3.5, 1.2) * water);
            }

            // hand-edited marker: a small open square, so the user can see what they own
            if (edited && live)
                ink(c, PT_INK, cvBoxLine(px, sp + float2(0.0, -rad - 9.0), float2(3.0, 3.0), 1.0) * water);

            if (isSel && live)
                ink(c, PT_ACCENT, cvRing(px, sp, max(rad, 3.0) + 7.0, 1.0) * water * 0.75);
        }

        // width dimension under the plan, so the diagram states its own scale
        {
            float2 d0 = float2(o.x - hIn.x, o.y + hOut.y + 13.0);
            float2 d1 = float2(o.x + hIn.x, d0.y);
            ink(c, PT_RULE, cvSeg(px, d0, d1, 1.0));
            ink(c, PT_RULE, cvSeg(px, d0 - float2(0, 4), d0 + float2(0, 4), 1.0));
            ink(c, PT_RULE, cvSeg(px, d1 - float2(0, 4), d1 + float2(0, 4), 1.0));
            ink(c, PT_DIM,  drawFix(px, float2((d0.x + d1.x) * 0.5 - 16.0, d0.y + 5.0), 10.0, half3.x * 2.0, 1u, 2u));
        }
    }

    // ======================================================================
    // SECTION STRIP — world (x, y) cut through the tank, same x scale as the plan
    // ======================================================================
    {
        float2 inH = float2(half3.x, (half3.y + fb) * 0.5) * L.scale;
        float2 inC = tpSecToPx(L, float2(0.0, (fb - half3.y) * 0.5));
        float2 outH = inH + float2(thick, thick * 0.5) * L.scale;
        float2 outC = inC + float2(0.0, thick * 0.5 * L.scale);

        ink(c, PT_WELL, cvBoxFill(px, outC, outH));
        ink(c, PT_RULE, cvBoxLine(px, outC, outH, 1.0));

        float2 wl0 = tpSecToPx(L, float2(-half3.x, 0.0));
        float2 wl1 = tpSecToPx(L, float2( half3.x, 0.0));
        float2 fl0 = tpSecToPx(L, float2(-half3.x, -half3.y));
        float2 fl1 = tpSecToPx(L, float2( half3.x, -half3.y));
        float2 rm0 = tpSecToPx(L, float2(-half3.x, fb));
        float2 rm1 = tpSecToPx(L, float2( half3.x, fb));

        // the still water body
        ink(c, PT_GRID, cvBoxFill(px, float2(inC.x, (wl0.y + fl0.y) * 0.5),
                                  float2(inH.x, abs(fl0.y - wl0.y) * 0.5)));

        // measured envelope, from live state
        if (peak > 1e-5)
        {
            float2 e0 = tpSecToPx(L, float2(0.0,  peak));
            float2 e1 = tpSecToPx(L, float2(0.0, -peak));
            float2 ec = float2(inC.x, (e0.y + e1.y) * 0.5);
            float2 eh = float2(inH.x, abs(e1.y - e0.y) * 0.5);
            ink(c, PT_MID, cvBoxFill(px, ec, eh) * 0.30);
            ink(c, overRim ? PT_ALARM : PT_MID, cvSeg(px, float2(wl0.x, e0.y), float2(wl1.x, e0.y), 1.4));
            ink(c, onFloor ? PT_ALARM : PT_MID, cvSeg(px, float2(wl0.x, e1.y), float2(wl1.x, e1.y), 1.4));

            // THE FAILURE MODE, drawn: the slice of the envelope that is above the glass rim.
            if (overRim)
            {
                float2 bh = float2(inH.x, abs(rm0.y - e0.y) * 0.5);
                float2 bc = float2(inC.x, (rm0.y + e0.y) * 0.5);
                ink(c, PT_ALARM, cvBoxFill(px, bc, bh) * 0.42);
                ink(c, PT_ALARM, cvBoxLine(px, bc, bh, 1.0));
            }
        }

        // waterline, rim, floor
        ink(c, PT_INK,  cvSeg(px, wl0, wl1, 1.6));
        ink(c, PT_DIM,  cvDash(px, rm0, rm1, 1.2, 7.0));
        ink(c, PT_DIM,  cvSeg(px, fl0, fl1, 1.6));
        ink(c, PT_DIM,  cvBoxLine(px, inC, inH, 1.2));

        // THE REFRACTED SUN RAY, drawn in world units and converted once. This is the only
        // place in the show that says WHY a caustic does not sit directly under the ripple
        // that made it: the ray bends at the surface and lands `offset` away, and that offset
        // grows with depth and with how far the sun is off vertical.
        {
            float3 sd = normalize(lamp.pos);
            float2 din = -normalize(float2(sd.x, sd.y));                  // incoming, travelling down
            float sinI = clamp(din.x, -1.0, 1.0);
            float sinT = sinI / 1.333;
            float cosT = sqrt(saturate(1.0 - sinT * sinT));

            float x0 = -half3.x * 0.30;
            float run = half3.y * (sinT / max(cosT, 1e-3));               // lateral travel to the floor
            float2 pEntry = tpSecToPx(L, float2(x0, 0.0));
            float2 pHit   = tpSecToPx(L, float2(x0 + run, -half3.y));

            // the air-side leg is drawn in PIXELS and clipped to the top of the strip: the
            // section box has only a freeboard of headroom, so a world-length ray would leave
            // the drawing and score a line across the plan above it
            float2 dirPx = float2(-din.x, din.y);                          // toward the sun, y down
            float legT = (pEntry.y - (TP_SEC_T * res.y + 5.0)) / max(-dirPx.y, 1e-3);
            float2 pStart = pEntry + dirPx * max(legT, 0.0);

            ink(c, PT_DIM, cvDash(px, pStart, pEntry, 1.1, 5.0) * 0.85);
            ink(c, PT_DIM, cvDash(px, pEntry, pHit, 1.1, 5.0) * 0.85);
            ink(c, PT_DIM, cvDisc(px, pHit, 2.4));
            ink(c, PT_RULE, cvDash(px, pEntry, tpSecToPx(L, float2(x0, -half3.y)), 1.0, 4.0) * 0.55);

            // the caustic offset itself, called out as a dimension inside the water
            float2 a0 = tpSecToPx(L, float2(x0, -half3.y)) - float2(0.0, 11.0);
            float2 a1 = pHit - float2(0.0, 11.0);
            ink(c, PT_RULE, cvSeg(px, a0, a1, 1.0));
            ink(c, PT_DIM,  drawFix(px, float2(min(a0.x, a1.x) + 2.0, a0.y - 12.0), 9.0, abs(run), 1u, 2u));
        }

        // depth dimension on the left of the section
        {
            float2 d0 = float2(outC.x - outH.x - 12.0, wl0.y);
            float2 d1 = float2(d0.x, fl0.y);
            ink(c, PT_RULE, cvSeg(px, d0, d1, 1.0));
            ink(c, PT_RULE, cvSeg(px, d0 - float2(4, 0), d0 + float2(4, 0), 1.0));
            ink(c, PT_RULE, cvSeg(px, d1 - float2(4, 0), d1 + float2(4, 0), 1.0));
        }

        // source stems at their real x, height proportional to amplitude share
        for (uint i = 0u; i < TP_SRCS; i++)
        {
            TpRec r = Plan[TP_SRC_0 + i];
            if (r.active < 0.5) continue;
            bool isSel = (sel > 0u) && ((sel - 1u) == (TP_SRC_0 + i));
            float2 b = tpSecToPx(L, float2(r.pos.x * half3.x, 0.0));
            float hgt = saturate(r.p0 / max(hdr.tint.z, 1e-3)) * (fb * L.scale) * 1.5;
            float3 col = isSel ? PT_ACCENT : PT_DIM;
            ink(c, col, cvSeg(px, b, b - float2(0.0, hgt), isSel ? 2.0 : 1.2));
            ink(c, col, cvDisc(px, b - float2(0.0, hgt), isSel ? 3.0 : 2.0));
        }
    }

    // ======================================================================
    // TYPE — title, readout column, status band
    // ======================================================================
    {
        float th = 13.0;
        float2 t0 = float2(TP_DRAW_L * res.x, 0.024 * res.y);
        ink(c, PT_INK, drawStr(px, t0, th, uint2(mf_pack1(29u,14u,28u,28u,14u), mf_pack1(27u,10u,0u,0u,0u)), 7u));       // TESSERA
        ink(c, PT_INK, drawStr(px, t0 + float2(strW(th, 8u), 0), th,
                               uint2(mf_pack1(25u,24u,24u,21u,0u), 0u), 4u));                                            // POOL
        ink(c, PT_DIM, drawStr(px, float2(TP_COL_L * res.x, t0.y), th * 0.85,
                               uint2(mf_pack1(25u,21u,10u,23u,MF_SLASH), mf_pack1(28u,14u,12u,29u,0u)), 9u));            // PLAN/SECT

        float2 cx0 = float2(TP_COL_L * res.x, TP_PLAN_T * res.y + 6.0);
        float rh = 15.0;
        float gh = 10.0;

        ink(c, PT_DIM, drawStr(px, cx0, gh, uint2(mf_pack1(28u,24u,30u,27u,12u), mf_pack1(14u,28u,0u,0u,0u)), 7u));      // SOURCES
        ink(c, PT_RULE, cvSeg(px, cx0 + float2(0.0, gh + 3.0), float2(TP_COL_R * res.x, cx0.y + gh + 3.0), 1.0));
        ink(c, PT_RULE, drawStr(px, cx0 + float2(strW(gh, 5u), gh + 6.0), gh * 0.9,
                                uint2(mf_pack1(10u,22u,25u,0u,0u), 0u), 3u));                                            // AMP
        ink(c, PT_RULE, drawStr(px, cx0 + float2(strW(gh, 11u), gh + 6.0), gh * 0.9,
                                uint2(mf_pack1(32u,10u,31u,0u,0u), 0u), 3u));                                            // WAV

        uint row = 1u;
        for (uint i = 0u; i < TP_SRCS && row < 10u; i++)
        {
            TpRec r = Plan[TP_SRC_0 + i];
            if (r.active < 0.5) continue;
            bool isSel = (sel > 0u) && ((sel - 1u) == (TP_SRC_0 + i));
            float3 col = isSel ? PT_ACCENT : PT_MID;
            float2 o = cx0 + float2(0.0, gh + 6.0 + (float)row * rh);

            if (isSel) ink(c, PT_ACCENT, drawGlyph(px, o - float2(11.0, 0.0), gh, MF_GT));
            ink(c, col, drawNum(px, o, gh, i, 2u));
            uint kl = (r.kind == KIND_EMIT) ? 14u : ((r.kind == KIND_SWELL) ? 28u : 13u);            // E / S / D
            ink(c, col, drawGlyph(px, o + float2(strW(gh, 3u), 0.0), gh, kl));
            ink(c, col, drawFix(px, o + float2(strW(gh, 5u), 0.0), gh, r.p0, 1u, 2u));
            ink(c, PT_DIM, drawFix(px, o + float2(strW(gh, 11u), 0.0), gh, r.p2, 1u, 3u));
            row++;
        }

        // the numbers the section is about
        float2 m0 = float2(TP_COL_L * res.x, TP_SEC_T * res.y + 4.0);
        ink(c, PT_DIM, drawStr(px, m0, gh, uint2(mf_pack1(25u,14u,10u,20u,0u), 0u), 4u));                                // PEAK
        ink(c, overRim ? PT_ALARM : PT_INK, drawFix(px, m0 + float2(strW(gh, 5u), 0), gh, peak, 1u, 3u));

        float2 m1 = m0 + float2(0.0, rh);
        ink(c, PT_DIM, drawStr(px, m1, gh, uint2(mf_pack1(27u,18u,22u,0u,0u), 0u), 3u));                                 // RIM
        ink(c, PT_MID, drawFix(px, m1 + float2(strW(gh, 5u), 0), gh, fb, 1u, 3u));

        float2 m2 = m1 + float2(0.0, rh);
        ink(c, PT_DIM, drawStr(px, m2, gh, uint2(mf_pack1(13u,14u,25u,29u,17u), 0u), 5u));                               // DEPTH
        ink(c, PT_MID, drawFix(px, m2 + float2(strW(gh, 6u), 0), gh, half3.y, 1u, 3u));

        float2 m3 = m2 + float2(0.0, rh);
        ink(c, PT_DIM, drawStr(px, m3, gh, uint2(mf_pack1(25u,18u,29u,12u,17u), 0u), 5u));                               // PITCH
        ink(c, PT_MID, drawFix(px, m3 + float2(strW(gh, 6u), 0), gh, pitch, 1u, 3u));

        if (overRim)
            ink(c, PT_ALARM, drawStr(px, m3 + float2(0.0, rh * 1.4), gh,
                                     uint2(mf_pack1(24u,31u,14u,27u,0u), mf_pack1(27u,18u,22u,0u,0u)), 7u));             // OVERRIM

        // status band: live source count and the six palette chips. A swatch's own colour is
        // information, so it keeps its hue — pulled back through the shared helper so it can
        // never outshine the accent.
        float2 s0 = float2(TP_DRAW_L * res.x, TP_STAT_T * res.y + 6.0);
        ink(c, PT_DIM, drawNum(px, s0, gh, (uint)liveN, 2u));
        ink(c, PT_DIM, drawStr(px, s0 + float2(strW(gh, 3u), 0), gh,
                               uint2(mf_pack1(28u,27u,12u,0u,0u), 0u), 3u));                                             // SRC

        float chipW = 22.0, chipH = 11.0;
        for (uint p = 0u; p < TP_PALS; p++)
        {
            float2 cc = float2(TP_COL_L * res.x + (float)p * (chipW + 4.0) + chipW * 0.5, s0.y + chipH * 0.5);
            ink(c, ptSampleFill(Plan[TP_PAL_0 + p].tint), cvBoxFill(px, cc, float2(chipW, chipH) * 0.5));
            ink(c, PT_RULE, cvBoxLine(px, cc, float2(chipW, chipH) * 0.5, 1.0));
        }
    }

    // frame
    ink(c, PT_RULE, cvBoxLine(px, res * 0.5, res * 0.5 - 1.5, 1.0));

    OutputUAV[DTid.xy] = float4(c, 1.0);
}
