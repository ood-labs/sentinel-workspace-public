// BR_Furnish / plate.hlsl -- the drawing under the furnishing plan's chrome: the per-pixel plan and
// section. The shared UI kit draws the panes' edges, the type, the selection's handles and family,
// the readouts (route, conversation circle, coffee gap, section cut) and the inspector and rules
// panes over this (ui.hlsl, from layout.hlsl's draw list).
//
// PLAN: north up, drawn the way an interior designer draws furniture -- seat cushions divided,
// arms and backs banded, tables with their bevel, lamps as the crossed-circle, plants as leaf
// rosettes, the rug with its border, medallion and fringe, an overhead pendant dashed. The walls
// are poched, the openings drawn with their swings; the hearth's keep-clear zone and the door
// swing turn red when a piece breaks them.
//
// SECTION: looking at one wall from the cut line, with HIDDEN LINES REMOVED -- each pixel finds the
// nearest silhouette in front of it first, so a chair in front of the sofa hides the sofa's arm.
// Nearer things draw in heavier ink, the way a section is weighted by hand.
//
// Mostly monochrome (plan_theme): amber is the selection, red a broken rule, nothing else has hue.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#include "furnish_defs.hlsli"
#include "furnish_layout.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<BRRec> FurnBuf : register(t0);

static float gS;        // px per metre of whatever pane is being drawn
static float gUi;

float aaLine(float d, float w) { return 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + 0.5, d); }
float cm(float dMetres, float widthPx) { return aaLine(dMetres * gS, widthPx); }
void ink(inout float3 col, float3 c, float a) { col = lerp(col, c, saturate(a)); }
float hatch(float2 P, float spacing, float angle, float w)
{
    float2 dir = float2(cos(angle), sin(angle));
    float s = dot(P, float2(-dir.y, dir.x));
    return aaLine(abs(frac(s / spacing + 0.5) - 0.5) * spacing, w);
}
float sdRect2(float2 p, float2 lo, float2 hi)
{
    float2 c = (lo + hi) * 0.5, h = (hi - lo) * 0.5;
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
float sdRRect2(float2 p, float2 lo, float2 hi, float r) { return sdRect2(p, lo + r, hi - r) - r; }
float rectLine(float2 p, float2 lo, float2 hi, float w) { return cm(abs(sdRect2(p, lo, hi)), w); }
float rectIn(float2 p, float2 lo, float2 hi) { return step(sdRect2(p, lo, hi), 0.0); }
float bx(float2 q, float x0, float y0, float x1, float y1) { return sdRect2(q, float2(x0, y0), float2(x1, y1)); }

BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }

// ---------------------------------------------------------------------------------------------
// PLAN SYMBOLS. l = point in the piece's local frame (metres, +z its front). Returns
// (fill coverage, outline distance, construction-line distance).
float3 planSymbol(FPiece p, float2 l)
{
    float w = p.size.x, d = p.size.z;
    int k = p.kind, v = p.variant;
    float sd = 1e9, ln = 1e9;
    if (k == FK_SOFA || k == FK_CHAIR)
    {
        bool chair = k == FK_CHAIR;
        float armW = chair ? ((v == 0) ? 0.11 : 0.16) : ((v == 1) ? 0.19 : 0.16);
        float backD = (chair && v == 1) ? 0.24 : 0.19;
        sd = sdRRect2(l, float2(-w, -d) * 0.5, float2(w, d) * 0.5, 0.04);
        float xi = w * 0.5 - armW;
        ln = min(ln, abs(l.y - (-d * 0.5 + backD)) + max(abs(l.x) - xi, 0.0) * 1e3);
        ln = min(ln, abs(abs(l.x) - xi) + max(-(l.y - (-d * 0.5 + backD * 0.4)), 0.0) * 1e3);
        float innerW = w - 2.0 * armW;
        int n = chair ? 1 : (int)clamp(round(innerW / 0.64), 1.0, 3.0);
        float cw = innerW / (float)n;
        float kx = clamp(round((l.x + innerW * 0.5) / cw), 1.0, max((float)n - 1.0, 1.0));
        if (n > 1) ln = min(ln, abs(l.x - (-innerW * 0.5 + kx * cw)) + max(-(l.y - (-d * 0.5 + backD)), 0.0) * 1e3);
        if (chair && v == 2) ln = min(ln, ilSdSeg(float2(abs(l.x), l.y), float2(xi, -d * 0.5 + 0.34), float2(w * 0.5, -d * 0.5 + 0.20)));
        if (!chair && v == 1) ln = min(ln, abs(abs(l.x) - (w * 0.5 - armW * 0.45)) + max(abs(l.y) - d * 0.45, 0.0) * 1e3);
    }
    else if (k == FK_COFFEE || k == FK_SIDE)
    {
        bool round_ = (k == FK_SIDE && v != 1) || (k == FK_COFFEE && v != 0);
        if (round_)
        {
            float r = w * 0.5;
            sd = length(l) - r;
            if (k == FK_COFFEE && v == 2) ln = min(abs(length(l - float2(0.15, 0.15) * sign(l)) - 0.012), abs(length(l) - r + 0.05));
            else ln = abs(length(l) - r * ((k == FK_COFFEE) ? 0.54 : 0.32));
        }
        else
        {
            sd = sdRect2(l, float2(-w, -d) * 0.5, float2(w, d) * 0.5);
            ln = abs(sdRect2(l, float2(-w, -d) * 0.5 + 0.045, float2(w, d) * 0.5 - 0.045));
        }
    }
    else if (k == FK_RUG)
    {
        sd = sdRect2(l, float2(-w, -d) * 0.5, float2(w, d) * 0.5);
        ln = min(abs(sdRect2(l, float2(-w, -d) * 0.5 + 0.10, float2(w, d) * 0.5 - 0.10)),
                 abs(sdRect2(l, float2(-w, -d) * 0.5 + 0.26, float2(w, d) * 0.5 - 0.26)));
        // medallion: a lozenge and a ring, the Persian field's centre
        float2 m = abs(l) / float2(w * 0.22, d * 0.22);
        ln = min(ln, abs(m.x + m.y - 1.0) * min(w, d) * 0.15);
        ln = min(ln, abs(length(l) - min(w, d) * 0.07));
        // fringe on the short ends
        float fz = abs(l.y) - d * 0.5;
        float fx = abs(frac(l.x / 0.035 + 0.5) - 0.5) * 0.035;
        if (fz > 0.0 && fz < 0.07 && abs(l.x) < w * 0.5 - 0.01) ln = min(ln, fx);
    }
    else if (k == FK_FLOORLAMP)
    {
        if (v == 0)
        {
            sd = length(l) - 0.17;
            float2 tip = float2(0, 1.23);
            ln = min(abs(length(l - tip) - 0.19), ilSdSeg(l, float2(0, 0.17), tip - float2(0, 0.19)));
            float2 q = l - tip;
            ln = min(ln, max(abs(abs(q.x) - abs(q.y)), length(q) - 0.17));
        }
        else
        {
            float rs = (v == 1) ? 0.25 : 0.21;
            sd = length(l) - rs;
            ln = max(abs(abs(l.x) - abs(l.y)), length(l) - rs + 0.02);
            if (v == 1) ln = min(ln, abs(length(l) - 0.27));
        }
    }
    else if (k == FK_TABLELAMP)
    {
        float rs = (v == 0) ? 0.19 : 0.16;
        sd = length(l) - rs;
        ln = max(abs(abs(l.x) - abs(l.y)), length(l) - rs + 0.02);
    }
    else if (k == FK_PENDANT)
    {
        sd = length(l) - w * 0.5;
        ln = min(abs(length(l) - 0.03), max(min(abs(l.x), abs(l.y)), length(l) - 0.08));
    }
    else if (k == FK_SHELF || k == FK_CONSOLE)
    {
        sd = sdRect2(l, float2(-w, -d) * 0.5, float2(w, d) * 0.5);
        if (k == FK_SHELF)
        {
            float fx = abs(frac(l.x / 0.04 + 0.5) - 0.5) * 0.04;
            ln = (abs(l.x) < w * 0.5 - 0.03 && l.y > -d * 0.5 + 0.02 && l.y < d * 0.5 - 0.05) ? fx : 1e9;
            ln = min(ln, abs(l.y - (d * 0.5 - 0.03)));
        }
        else ln = min(abs(abs(l.x) - w / 6.0) + max(abs(l.y) - d * 0.5, 0.0) * 1e3, abs(l.y - (d * 0.5 - 0.02)));
    }
    else if (k == FK_PLANT)
    {
        float R = w * 0.5;
        float a = atan2(l.y, l.x + 1e-6);
        float lobes = (v == 1) ? 0.0 : ((v == 0) ? 7.0 : 11.0);
        float rr = R * ((v == 1) ? 0.55 : (0.80 + 0.20 * cos(lobes * a + p.seed * 6.28)));
        sd = length(l) - rr;
        float pot = (v == 1) ? 0.15 : 0.20;
        ln = abs(length(l) - pot * 0.85);
        if (v == 1)
        {
            float sa = frac(a / 6.2831853 * 9.0 + p.seed) - 0.5;
            ln = min(ln, max(abs(sa) * length(l) * 0.7, length(l) - R * 0.9));
        }
        else ln = min(ln, max(abs(sin(lobes * 0.5 * a + p.seed * 3.14)) * length(l) * 0.4, length(l) - rr * 0.9));
    }
    else if (k == FK_ART)
    {
        sd = sdRect2(l, float2(-w * 0.5, 0.0), float2(w * 0.5, max(d, 0.045)));
        ln = 1e9;
    }
    else if (k == FK_CUSHION)
    {
        sd = sdRRect2(l, float2(-w * 0.5, -0.08), float2(w * 0.5, 0.08), 0.05);
        ln = 1e9;
    }
    else if (k == FK_BOOKS)
    {
        sd = sdRect2(l, float2(-0.13, -0.10), float2(0.13, 0.10));
        ln = abs(l.y + 0.03);
    }
    else if (k == FK_VASE)
    {
        sd = length(l) - 0.07;
        float a = atan2(l.y, l.x + 1e-6);
        ln = (length(l) < 0.13) ? abs(frac(a / 6.2831853 * 5.0 + p.seed) - 0.5) * length(l) * 6.28 / 5.0 : 1e9;
    }
    else if (k == FK_LOGS)
    {
        sd = min(min(ilSdSeg(l, float2(-0.25, -0.03), float2(0.25, 0.05)) - 0.05, ilSdSeg(l, float2(-0.22, 0.09), float2(0.24, -0.05)) - 0.05), 1e9);
        ln = 1e9;
    }
    return float3(saturate(0.5 - sd * gS), abs(sd), ln);
}

// ---------------------------------------------------------------------------------------------
// SECTION SILHOUETTES. q = (u relative to the piece's projected centre, height above the floor).
// fu = how much of the piece's forward axis runs along the section's horizontal (+1 / -1 is a
// side view facing right / left; ~0 a front or back view). Returns (silhouette sd, line distance).
float2 secSilhouette(FPiece p, float2 q, float fu, float roomH)
{
    float w = p.size.x, h = p.size.y, d = p.size.z;
    int k = p.kind, v = p.variant;
    q.y -= p.y0;
    bool side = abs(fu) > 0.7;
    float sgn = (fu >= 0.0) ? 1.0 : -1.0;
    float sd = 1e9, ln = 1e9;
    if (k == FK_SOFA || k == FK_CHAIR)
    {
        bool chair = k == FK_CHAIR;
        float legH = chair ? ((v == 0) ? 0.17 : 0.10) : ((v == 1) ? 0.07 : 0.13);
        float seatTop = chair ? ((v == 0) ? 0.41 : 0.43) : 0.45;
        float armW = chair ? ((v == 0) ? 0.11 : 0.16) : ((v == 1) ? 0.19 : 0.16);
        float armTop = chair ? ((v == 2) ? 0.64 : (v == 0) ? 0.56 : 0.66) : ((v == 1) ? 0.66 : 0.62);
        float backD = (chair && v == 1) ? 0.24 : 0.19;
        float backTop = h - ((chair && v == 2) ? 0.0 : 0.04);
        if (!side)
        {
            sd = min(bx(q, -w * 0.5, legH, w * 0.5, armTop), bx(q, -w * 0.5 + armW, legH, w * 0.5 - armW, backTop));
            sd = min(sd, bx(float2(abs(q.x), q.y), w * 0.5 - 0.11, 0.0, w * 0.5 - 0.075, legH + 0.01));
            ln = abs(q.y - seatTop) + max(abs(q.x) - (w * 0.5 - armW), 0.0) * 1e3;
            ln = min(ln, abs(abs(q.x) - (w * 0.5 - armW)) + max(q.y - armTop, 0.0) * 1e3 + max(legH + 0.05 - q.y, 0.0) * 1e3);
        }
        else
        {
            float z = q.x * sgn;
            sd = min(bx(float2(z, q.y), -d * 0.5, legH, d * 0.5, armTop), bx(float2(z, q.y), -d * 0.5, legH, -d * 0.5 + backD + 0.08, backTop));
            sd = min(sd, bx(float2(abs(z), q.y), d * 0.5 - 0.11, 0.0, d * 0.5 - 0.075, legH + 0.01));
            ln = abs(q.y - seatTop) + max(-(z - (-d * 0.5 + backD)), 0.0) * 1e3;
        }
        return float2(sd, ln);
    }
    float span = side ? d : w;
    float x = side ? q.x * sgn : q.x;
    if (k == FK_COFFEE || k == FK_SIDE)
    {
        bool round_ = (k == FK_SIDE && v != 1) || (k == FK_COFFEE && v != 0);
        float s2 = round_ ? w : span;
        if (k == FK_COFFEE && v == 2) { sd = sdRRect2(q, float2(-s2 * 0.5, 0.03), float2(s2 * 0.5, h), 0.06); return float2(sd, abs(q.y - h * 0.55)); }
        if (k == FK_SIDE && v == 2) { sd = sdRRect2(q, float2(-s2 * 0.5, 0.0), float2(s2 * 0.5, h), 0.03); return float2(sd, abs(q.y - h + 0.03)); }
        float top = bx(q, -s2 * 0.5, h - 0.032, s2 * 0.5, h);
        if (k == FK_COFFEE && v == 1) sd = min(bx(q, -s2 * 0.5, h - 0.06, s2 * 0.5, h), bx(q, -s2 * 0.27, 0.0, s2 * 0.27, h - 0.06));
        else if (k == FK_SIDE && v == 0) sd = min(min(top, bx(q, -0.032, 0.0, 0.032, h)), bx(q, -s2 * 0.36, 0.0, s2 * 0.36, 0.028));
        else
        {
            sd = min(top, bx(float2(abs(q.x), q.y), s2 * 0.5 - 0.105, 0.0, s2 * 0.5 - 0.065, h));
            sd = min(sd, bx(q, -s2 * 0.5 + 0.06, h - 0.085, s2 * 0.5 - 0.06, h - 0.03));
            if (k == FK_SIDE) sd = min(sd, bx(q, -s2 * 0.5 + 0.07, 0.14, s2 * 0.5 - 0.07, 0.16));
        }
        return float2(sd, 1e9);
    }
    if (k == FK_FLOORLAMP)
    {
        if (v == 0)
        {
            sd = min(bx(q, -0.17, 0.0, 0.17, 0.04), bx(q, -0.012, 0.0, 0.012, 1.30));
            // the arc, in the plane of the lamp's forward axis, projected
            float2 prev = float2(0, 1.30);
            [unroll] for (int i = 1; i <= 8; i++)
            {
                float th = 3.32 * (float)i / 8.0;
                float lz = 0.62 - 0.62 * cos(th);
                float2 cur = float2(fu * lz, 1.30 + 0.62 * sin(th));
                sd = min(sd, ilSdSeg(q, prev, cur) - 0.011);
                prev = cur;
            }
            float2 tip = float2(fu * 1.23, 1.13);
            float2 r = q - tip;
            sd = min(sd, max(length(r) - 0.19, r.y - 0.06));
            return float2(sd, 1e9);
        }
        float yb = (v == 1) ? 1.24 : 1.30, yt = (v == 1) ? 1.56 : 1.62;
        float rb = (v == 1) ? 0.25 : 0.21, rt = (v == 1) ? 0.22 : 0.18;
        float t = saturate((q.y - yb) / (yt - yb));
        float shade = max(abs(q.x) - lerp(rb, rt, t), abs(q.y - (yb + yt) * 0.5) - (yt - yb) * 0.5);
        float stem = (v == 1) ? min(ilSdSeg(q, float2(-0.27, 0.0), float2(0, yb)), ilSdSeg(q, float2(0.27, 0.0), float2(0, yb))) - 0.012
                              : min(bx(q, -0.012, 0.0, 0.012, yb), bx(q, -0.14, 0.0, 0.14, 0.024));
        return float2(min(shade, stem), 1e9);
    }
    if (k == FK_TABLELAMP)
    {
        float yb = 0.34, yt = (v == 0) ? 0.60 : 0.56;
        float rb = (v == 0) ? 0.19 : 0.16, rt = (v == 0) ? 0.155 : 0.095;
        float t = saturate((q.y - yb) / (yt - yb));
        float shade = max(abs(q.x) - lerp(rb, rt, t), abs(q.y - (yb + yt) * 0.5) - (yt - yb) * 0.5);
        float base = (v == 0) ? min(length((q - float2(0, 0.13)) / float2(0.13, 0.125)) - 1.0, length((q - float2(0, 0.29)) / float2(0.075, 0.08)) - 1.0) * 0.1
                              : min(bx(q, -0.016, 0.0, 0.016, yb), bx(q, -0.075, 0.0, 0.075, 0.024));
        return float2(min(shade, base), 1e9);
    }
    if (k == FK_PENDANT)
    {
        float topY = roomH - p.y0;
        float capY = (v == 1) ? 0.55 : (v == 2) ? 0.24 : 0.41;
        float cord = bx(q, -0.004, capY, 0.004, topY);
        float body;
        if (v == 0) body = length(q - float2(0, 0.20)) - 0.20;
        else if (v == 1) body = (length((q - float2(0, 0.27)) / float2(0.25, 0.27)) - 1.0) * 0.25;
        else body = max(length(q) - 0.23, -q.y);
        return float2(min(cord, body), 1e9);
    }
    if (k == FK_SHELF || k == FK_CONSOLE)
    {
        if (k == FK_CONSOLE)
        {
            sd = min(bx(q, -span * 0.5, 0.13, span * 0.5, h), bx(float2(abs(q.x), q.y), span * 0.5 - 0.09, 0.0, span * 0.5 - 0.06, 0.14));
            ln = side ? 1e9 : abs(abs(q.x) - span / 6.0) + max(abs(q.y - (h + 0.13) * 0.5) - (h - 0.13) * 0.5 + 0.03, 0.0) * 1e3;
            return float2(sd, ln);
        }
        sd = bx(q, -span * 0.5, 0.0, span * 0.5, h);
        int shelves = (v == 0) ? 5 : 4;
        float pitch = (h - 0.085 - 0.024) / (float)shelves;
        float row = floor((q.y - 0.085) / pitch);
        float ry = 0.085 + row * pitch;
        ln = abs(frac((q.y - 0.085) / pitch + 0.5) - 0.5) * pitch;
        if (!side && q.y > 0.09 && q.y < h - 0.03)
        {
            // book spines: verticals of varying height in each row
            float bk = floor(q.x / 0.038);
            float bh = lerp(0.20, min(pitch - 0.05, 0.31), frac(sin(bk * 12.9898 + row * 78.233 + p.seed * 37.0) * 43758.5453));
            float fx = abs(frac(q.x / 0.038) - 0.5) * 0.038;
            if (q.y - ry < bh && abs(q.x) < span * 0.5 - 0.03) ln = min(ln, 0.019 - fx);
        }
        return float2(sd, ln);
    }
    if (k == FK_PLANT)
    {
        float potH = (v == 1) ? 0.30 : 0.36;
        float rT = (v == 1) ? 0.15 : 0.20, rB = (v == 1) ? 0.12 : 0.15;
        float t = saturate(q.y / potH);
        float pot = max(abs(q.x) - lerp(rB, rT, t), abs(q.y - potH * 0.5) - potH * 0.5);
        float fol;
        if (v == 1)
        {
            float bl = abs(frac(q.x / 0.05 + 0.5) - 0.5) * 0.05 - 0.012 * (1.0 - saturate((q.y - potH) / (h - potH)));
            fol = max(max(bl, abs(q.x) - 0.14), abs(q.y - (potH + h) * 0.5) - (h - potH) * 0.5);
        }
        else
        {
            float top0 = (v == 0) ? potH + 0.35 : h - 0.7;
            float2 c = float2(0, (top0 + h) * 0.5);
            float2 rr = float2(w * 0.5, (h - top0) * 0.5);
            float a = atan2(q.y - c.y, q.x + 1e-6);
            fol = (length((q - c) / rr) - 1.0 - 0.10 * sin(a * 9.0 + p.seed * 6.28)) * min(rr.x, rr.y);
            fol = min(fol, bx(q, -0.015, potH, 0.015, top0 + 0.1));
        }
        return float2(min(pot, fol), 1e9);
    }
    if (k == FK_ART)
    {
        if (side) return float2(bx(q, -max(d, 0.03) * 0.5, 0.0, max(d, 0.03) * 0.5, h), 1e9);     // edge-on
        if (v == 2) { sd = length(q - float2(0, h * 0.5)) - w * 0.5; return float2(sd, abs(length(q - float2(0, h * 0.5)) - w * 0.5 + 0.035)); }
        sd = bx(q, -w * 0.5, 0.0, w * 0.5, h);
        ln = (v == 0) ? abs(bx(q, -w * 0.5 + 0.032, 0.032, w * 0.5 - 0.032, h - 0.032)) : abs(q.y - h * 0.42) + max(abs(q.x) - w * 0.5, 0.0);
        return float2(sd, ln);
    }
    if (k == FK_CUSHION) return float2(sdRRect2(q, float2(-w * 0.5, 0.0), float2(w * 0.5, h), 0.05), 1e9);
    if (k == FK_BOOKS) return float2(min(min(bx(q, -0.13, 0.0, 0.13, 0.04), bx(q, -0.11, 0.04, 0.12, 0.08)), bx(q, -0.12, 0.08, 0.10, 0.12)), 1e9);
    if (k == FK_VASE)
    {
        float body = (length((q - float2(0, 0.13)) / float2(0.08, 0.13)) - 1.0) * 0.08;
        float stems = 1e9;
        [unroll] for (int i = 0; i < 5; i++)
        {
            float a = (float)i * 1.2566 + p.seed;
            stems = min(stems, ilSdSeg(q, float2(0, 0.22), float2(sin(a) * 0.12, 0.52 + 0.06 * frac((float)i * 0.61))) - 0.003);
        }
        return float2(min(body, stems), 1e9);
    }
    if (k == FK_LOGS) return float2(min(min(bx(q, -0.27, 0.01, 0.27, 0.11), bx(q, -0.22, 0.10, 0.22, 0.20)), bx(q, -0.29, 0.0, 0.29, 0.02)), 1e9);
    return float2(1e9, 1e9);
}

// ---------------------------------------------------------------------------------------------
// shared opening drawing for the section (a, y) frame of one wall
void drawWallElevation(inout float3 col, float2 q, FSection S, BRRoom r, BROpening ops[SHELL_OPEN_MAX], float uOf0, float uSign)
{
    // q = (u, y). Opening a -> u: u = uOf0 + uSign * a
    float3 lc = PT_DIM, tc = PT_RULE * 1.6;
    // baseboard, picture rail, crown
    if (r.baseH > 0.01) ink(col, tc, cm(abs(q.y - r.baseH), 0.9));
    if (r.railH > 0.01) ink(col, tc, cm(abs(q.y - r.railH), 0.8));
    if (r.crown > 0.01) ink(col, tc, cm(abs(q.y - (r.H - r.crown)), 0.9));
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = ops[i];
        if (!o.active || o.wall != S.wall) continue;
        float u = uOf0 + uSign * o.a;
        float hw = o.width * 0.5;
        float2 p = float2(q.x - u, q.y);
        if (abs(p.x) > hw + 0.5) continue;
        if (o.kind == OPEN_FIREPLACE)
        {
            ink(col, PT_WELL * 1.6, rectIn(p, float2(-hw, 0), float2(hw, r.H)));
            ink(col, tc, cm(abs(abs(p.x) - hw), 0.9));
            float mh = o.height;
            ink(col, lc, rectLine(p, float2(-hw - 0.06, mh - 0.085), float2(hw + 0.06, mh), 1.0));
            ink(col, lc, rectLine(p, float2(-hw + 0.05, 0.0), float2(hw - 0.05, mh - 0.10), 0.9));
            float fbw = o.cols * 0.5, fbh = o.rows, capH = fbw * 0.55, cy = fbh - capH;
            float2 uv = float2(abs(p.x), p.y - cy);
            float dCap = (length(float2(uv.x / fbw, max(uv.y, 0.0) / capH)) - 1.0) * capH;
            float dBox = min(dCap, sdRect2(uv, float2(-fbw, 0.04 - cy), float2(fbw, 0.0)));
            ink(col, PT_FIELD, step(dBox, 0.0));
            ink(col, lc, cm(abs(dBox), 1.0) * step(0.045, p.y));
            ink(col, lc, rectLine(p, float2(-hw - 0.12, 0.0), float2(hw + 0.12, 0.035), 0.9));
            continue;
        }
        if (o.kind == OPEN_ARCH)
        {
            float cy = o.sill + o.height - hw;
            float2 uv = float2(abs(p.x), p.y - cy);
            float dS = min(length(uv) - hw, sdRect2(uv, float2(-hw, o.sill - cy), float2(hw, 0.0)));
            ink(col, PT_FIELD, step(dS, 0.0));
            ink(col, lc, cm(abs(dS), 1.0) * step(0.005, p.y));
            continue;
        }
        float2 lo = float2(-hw, o.sill), hi = float2(hw, o.sill + o.height);
        ink(col, PT_FIELD, rectIn(p, lo, hi));
        ink(col, tc, rectLine(p, lo - float2(0.075, 0.0), hi + float2(0.075, 0.075), 0.8));
        ink(col, lc, rectLine(p, lo, hi, 1.0));
        if (brOpenIsWindow(o.kind))
        {
            float mid = (lo.y + hi.y) * 0.5;
            ink(col, lc * 0.8, cm(abs(p.y - mid), 0.8) * step(abs(p.x), hw));
            ink(col, lc * 0.8, cm(abs(p.x), 0.7) * step(lo.y, p.y) * step(p.y, hi.y));
            ink(col, tc, rectLine(p, float2(-hw - 0.11, o.sill - 0.03), float2(hw + 0.11, o.sill), 0.8));
        }
        if (o.kind == OPEN_DOOR)
        {
            ink(col, tc, rectLine(p, float2(-hw + 0.11, 0.20), float2(hw - 0.11, 0.82), 0.8));
            ink(col, tc, rectLine(p, float2(-hw + 0.11, 1.06), float2(hw - 0.11, o.height - 0.11), 0.8));
        }
    }
}

// ---------------------------------------------------------------------------------------------
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
    BROpening ops[SHELL_OPEN_MAX];
    [unroll] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++)
    {
        if (haveShell) ops[oi] = brOpeningFromRec(sh(5 + oi));
        else { ops[oi] = brOpeningFromRec(sh(0)); ops[oi].active = false; }
    }

    FLayout L = fLayout(res, r);
    gUi = L.ui;
    float3 col = IL_FIELD;

    BRRec ed = FurnBuf[FURN_EDITOR];
    int sel = (int)round(ed.head.y);
    if (sel < -1 || sel >= FS_COUNT) sel = -1;
    int secWall = clamp((int)round(ed.head.z), 0, 3);
    float cutD = ed.meta.w;
    BRRec rules = FurnBuf[FURN_RULES];
    int ruleBits = (int)round(rules.head.w);
    BRRec g0 = FurnBuf[FURN_ROUTE0];
    int doorSlot = (int)round(g0.meta.w);
    FSection S = fSection(L, r, secWall, cutD);

    // the two drawing panes' cards (the kit draws their edges, header rules and titles)
    float dPlan = ilSdBox(P, L.planPane, IL_RADIUS * gUi), dSec = ilSdBox(P, L.secPane, IL_RADIUS * gUi);
    ilOver(col, IL_PANEL, max(ilFill(dPlan), ilFill(dSec)));

    // =========================================================================================
    // PLAN
    if (fInRect(P, L.planR, 0.0))
    {
        gS = L.s;
        float2 wp = fPlanWorld(L, P);
        float T = r.T;
        bool inRoom = wp.x >= r.x0 && wp.x <= r.x1 && wp.y >= r.z0 && wp.y <= r.z1;
        bool inOuter = wp.x >= r.x0 - T && wp.x <= r.x1 + T && wp.y >= r.z0 - T && wp.y <= r.z1 + T;
        if (inRoom)
        {
            ink(col, PT_WELL, 1.0);
            // half-metre grid, the scale a furniture plan is read at
            float2 gq = abs(frac(wp / 0.5 + 0.5) - 0.5) * 0.5;
            ink(col, PT_GRID, cm(min(gq.x, gq.y), 0.8) * 0.8);
        }
        // poche
        float cut = 0.0;
        [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
        {
            BROpening o = ops[i];
            if (!o.active || !brOpenIsHole(o.kind)) continue;
            float along = brWallAlongX(o.wall) ? wp.x : wp.y;
            float2 n = brWallNormal(o.wall);
            float plane = brWallPlane(r, o.wall);
            float d = brWallAlongX(o.wall) ? (wp.y - plane) * n.y : (wp.x - plane) * n.x;
            if (abs(along - o.a) <= o.width * 0.5 && d <= 0.0 && d >= -T) cut = 1.0;
        }
        if (inOuter && !inRoom && cut < 0.5)
        {
            ink(col, PT_RULE * 0.55, 1.0);
            ink(col, PT_RULE * 1.5, hatch(P, 5.0 * gUi, 0.785, 1.0));
        }
        float dIn = abs(sdRect2(wp, float2(r.x0, r.z0), float2(r.x1, r.z1)));
        float dOut = abs(sdRect2(wp, float2(r.x0 - T, r.z0 - T), float2(r.x1 + T, r.z1 + T)));
        ink(col, PT_MID, cm(dOut, 1.2) * (1.0 - cut));
        ink(col, PT_INK * 0.85, cm(dIn, 1.4) * (1.0 - cut));
        // openings
        [loop] for (int j = 0; j < SHELL_OPEN_MAX; j++)
        {
            BROpening o = ops[j];
            if (!o.active) continue;
            float along = brWallAlongX(o.wall) ? wp.x : wp.y;
            float2 n = brWallNormal(o.wall);
            float plane = brWallPlane(r, o.wall);
            float d = brWallAlongX(o.wall) ? (wp.y - plane) * n.y : (wp.x - plane) * n.x;
            float hw = o.width * 0.5;
            float2 q = float2(along - o.a, d);
            if (abs(q.x) > hw + 1.2 || d < -T - 0.1 || d > max(o.width, 1.4) + 0.2) continue;
            float3 lc = PT_MID;
            if (o.kind == OPEN_FIREPLACE)
            {
                float dep = o.depth;
                float inB = rectIn(q, float2(-hw, 0), float2(hw, dep));
                float fb = o.cols * 0.5;
                float inBox = rectIn(q, float2(-fb, dep - 0.42), float2(fb, dep));
                ink(col, PT_RULE * 0.55, inB * (1.0 - inBox));
                ink(col, PT_RULE * 1.5, inB * (1.0 - inBox) * hatch(P, 5.0 * gUi, 0.785, 1.0));
                ink(col, PT_FIELD, inBox);
                ink(col, lc, rectLine(q, float2(-hw, 0), float2(hw, dep), 1.1));
                ink(col, lc, rectLine(q, float2(-hw - 0.12, dep), float2(hw + 0.12, dep + 0.48), 0.9) * step(dep + 0.001, q.y));
                // keep-clear zone in front of the hearth
                bool bad = (ruleBits & RULE_HEARTH) != 0;
                float zone = rectLine(q, float2(-hw - 0.12, dep + 0.48), float2(hw + 0.12, dep + 0.48 + 0.75), 0.8);
                float dash = step(frac((q.x + q.y) * gS / 9.0), 0.5);
                ink(col, bad ? PT_ALARM : PT_RULE * 1.6, zone * dash * step(dep + 0.48 + 0.002, q.y));
                continue;
            }
            if (o.kind == OPEN_ARCH)
            {
                float dash = step(fmod(abs(q.x) * gS, 9.0), 5.0);
                ink(col, lc, step(abs(q.x), hw) * dash * max(cm(abs(d), 1.0), cm(abs(d + T), 1.0)));
                ink(col, lc, step(-T, d) * step(d, 0.0) * cm(abs(abs(q.x) - hw), 1.0));
                continue;
            }
            ink(col, lc, step(-T, d) * step(d, 0.0) * cm(abs(abs(q.x) - hw), 1.0));
            if (brOpenIsGlazed(o.kind) && o.kind != OPEN_FRENCH)
            {
                float onSpan = step(abs(q.x), hw);
                ink(col, lc, onSpan * cm(abs(d + T * 0.5 - 0.018), 0.8));
                ink(col, lc, onSpan * cm(abs(d + T * 0.5 + 0.018), 0.8));
                if (o.radiator) ink(col, PT_RULE * 1.5, rectLine(q, float2(-hw + 0.06, 0.05), float2(hw - 0.06, 0.15), 0.8));
            }
            else
            {
                bool bad = (ruleBits & RULE_DOOR) != 0 && j == doorSlot;
                float3 dc = bad ? PT_ALARM : lc;
                float2 hinge = float2(-hw, 0);
                ink(col, dc, cm(ilSdSeg(q, hinge, float2(-hw, o.width)), 1.2));
                float2 rel = q - hinge;
                float ang = atan2(rel.y, rel.x + 1e-6);
                ink(col, dc, step(0.0, ang) * step(ang, 1.5708) * cm(abs(length(rel) - o.width), 0.9) * 0.9);
            }
        }

        // furniture: floor bodies and the rug, then things on top, then overhead and wall pieces
        [loop] for (int layer = 0; layer < 3; layer++)
        {
            [loop] for (int s = 0; s < FS_COUNT; s++)
            {
                FPiece p = fpFromRec(FurnBuf[s]);
                if (p.kind == FK_NONE) continue;
                int lyr = (p.kind == FK_RUG) ? 0 : (p.kind == FK_TABLELAMP || p.kind == FK_CUSHION || p.kind == FK_BOOKS || p.kind == FK_VASE || p.kind == FK_PENDANT) ? 2 : 1;
                if (p.kind == FK_RUG && layer != 0) continue;
                if (p.kind != FK_RUG && lyr != layer) continue;
                float2 l = toLocal2(p.pos, p.yaw, wp);
                float reach = length(p.size.xz) * 0.5 + ((p.kind == FK_FLOORLAMP) ? 1.5 : 0.2);
                if (length(l) > reach) continue;
                bool hidden = (p.flags & FF_HIDDEN) != 0;
                bool isSel = s == sel;
                bool alarm = (p.flags & FF_ALARM) != 0 && !hidden;
                bool edited = (p.flags & FF_EDITED) != 0;
                float3 sym = planSymbol(p, l);
                float3 lc = alarm ? PT_ALARM : (isSel ? PT_ACCENT : (edited ? PT_INK : PT_MID));
                if (hidden && !isSel && !edited) continue;      // the layering left it out: no ghost
                if (hidden)
                {
                    // a ghost: dashed outline, no fill
                    float dash = step(frac((wp.x + wp.y) * gS / 8.0), 0.5);
                    ink(col, isSel ? PT_ACCENT : PT_RULE * 1.4, cm(sym.y, 0.9) * dash);
                    continue;
                }
                if (p.kind == FK_PENDANT)
                {
                    float dash = step(frac(atan2(l.y, l.x) / 6.2831853 * 18.0), 0.5);
                    ink(col, lc, cm(sym.y, isSel ? 1.6 : 1.0) * dash);
                    ink(col, PT_DIM, cm(sym.z, 0.8));
                    continue;
                }
                float fillC = (p.kind == FK_RUG) ? 0.75 : 1.0;
                float3 fc = (p.kind == FK_RUG) ? PT_GRID * 1.9 : ((p.kind == FK_PLANT) ? PT_RULE * 0.75 : PT_RULE * 0.62);
                ink(col, fc, sym.x * fillC);
                ink(col, (p.kind == FK_RUG) ? PT_RULE * 1.5 : PT_DIM, cm(sym.z, 0.8) * sym.x);
                if (p.kind == FK_RUG) ink(col, PT_RULE * 1.6, cm(sym.z, 0.8) * (1.0 - sym.x) * step(abs(l.y), p.size.z * 0.5 + 0.08));
                ink(col, lc, cm(sym.y, isSel ? 1.8 : 1.15));
            }
        }
    }

    // =========================================================================================
    // SECTION
    else if (fInRect(P, L.secR, 0.0))
    {
        gS = S.ss;
        float2 uy = fSecUY(S, P);
        // the wall itself
        bool onWall = uy.x >= S.u0 && uy.x <= S.u1 && uy.y >= 0.0 && uy.y <= r.H;
        if (onWall) ink(col, PT_WELL * 1.25, 1.0);
        // along-wall a -> u
        float uA0 = dot(brWallPoint(r, secWall, 0.0, 0.0), S.t);
        float uA1 = dot(brWallPoint(r, secWall, 1.0, 0.0), S.t);
        float uSign = uA1 - uA0;
        if (onWall) drawWallElevation(col, uy, S, r, ops, uA0, uSign);
        ink(col, PT_INK * 0.8, cm(abs(sdRect2(uy, float2(S.u0, 0.0), float2(S.u1, r.H))), 1.3));
        ink(col, PT_RULE, cm(abs(uy.y), 1.0) * step(S.u0 - 0.3, uy.x) * step(uy.x, S.u1 + 0.3));

        // pieces with hidden lines removed: the first sweep finds the nearest silhouette covering
        // this pixel, the second draws fill + edges only for what is at (or in front of) that depth
        float frontD = -1e9; int frontS = -1;
        float edgeBest = 1e9, lineBest = 1e9; int edgeS = -1;
        [loop] for (int it = 0; it < 2 * FS_COUNT; it++)
        {
            int pz = it / FS_COUNT, s = it % FS_COUNT;
            FPiece p = fpFromRec(FurnBuf[s]);
            if (!fpVisible(p) || p.kind == FK_RUG) continue;
            float dep = fSecDepth(S, r, p.pos);
            if (dep > cutD || dep < -0.6) continue;
            if (pz == 1 && dep < frontD - 0.02) continue;
            float uc = fSecU(S, p.pos);
            float fu = dot(fwd2(p.yaw), S.t);
            float2 sil = secSilhouette(p, float2(uy.x - uc, uy.y), fu, r.H);
            if (pz == 0)
            {
                if (sil.x < 0.0 && dep > frontD) { frontD = dep; frontS = s; }
            }
            else
            {
                if (abs(sil.x) < edgeBest) { edgeBest = abs(sil.x); edgeS = s; }
                if (s == frontS) lineBest = sil.y;
            }
        }
        if (frontS >= 0)
        {
            float near01 = saturate(frontD / max(cutD, 0.5));
            ink(col, lerp(PT_RULE * 0.35, PT_RULE * 0.75, near01), 0.92);
            ink(col, PT_DIM * lerp(0.6, 1.0, near01), cm(lineBest, 0.8));
        }
        if (edgeS >= 0)
        {
            FPiece f = fpFromRec(FurnBuf[edgeS]);
            float dep = fSecDepth(S, r, f.pos);
            float near01 = saturate(dep / max(cutD, 0.5));
            bool isSel = edgeS == sel;
            bool alarm = (f.flags & FF_ALARM) != 0;
            float3 lc = alarm ? PT_ALARM : (isSel ? PT_ACCENT : lerp(PT_DIM, PT_INK, near01));
            ink(col, lc, cm(edgeBest, lerp(0.9, 1.8, near01) + (isSel ? 0.6 : 0.0)));
        }
    }

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
