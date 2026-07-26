// Style Authority - live specimen sheet.
//
// Draws every v3 primitive at the currently published theme, plus a readout
// table of the exact values leaving the node. Nothing here is a mock-up: the
// specimens read the same buffer the control outputs are taken from, so what
// you see is what the rest of the graph receives.
//
// Layout rects are PROPORTIONAL to the output; every stroke and glyph is drawn
// in PIXELS. That hybrid is what survives an extent change. Phase 3A measured
// the v1 stations, which are normalized throughout, going illegible at their
// real dock extents.
#include "../_shared/ui/sui3_controls.hlsli"
#include "layout.hlsli"

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<float4> Theme : register(t0);

float4 RP(float4 n, float2 R) { return float4(n.xy * R, n.zw * R); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 R = _Resolution.xy;
    float2 P = ((float2)tid.xy) + 0.5;

    float4 t0 = Theme[0];   // title, section, body, exposure
    float4 t1 = Theme[1];   // padding, section gap, control height, control gap
    float4 t2 = Theme[2];   // accent rgb, specimen value
    float4 t3 = Theme[3];   // pad x, pad y (up=more), toggle, bank

    Sui3Theme T = sui3ThemeExposed(t2.rgb, t0.w);

    // Layout comes from layout.hlsli so the events pass hit-tests EXACTLY the
    // rects drawn here. Integer glyph scale keeps the bitmap face crisp; two
    // steps only, chosen so 640x360 and 1600x900 both land on a legible size.
    SaLayout L = saLayout(R, t0.x, t0.y, t1.x, t1.y, t1.z, t1.w);
    float sB = L.sB, sT = L.sT, sS = L.sS;
    float pad = L.pad;
    float3 col = T.field;

    // ---- header ------------------------------------------------------------
    float headY = L.headY;
    col += T.ink * sui3TextLong(P, float2(pad, headY), sT,
        S_S,S_T,S_Y,S_L,S_E,S_SP,S_A,S_U,S_T,S_H,S_O,S_R,
        S_I,S_T,S_Y, 0,0,0,0,0,0,0,0,0);
    col += T.dim * sui3TextLong(P, float2(pad, headY + 13.0 * sT), sB,
        S_L,S_I,S_V,S_E,S_SP,S_T,S_H,S_E,S_M,S_E,S_SP,S_S,
        S_O,S_U,S_R,S_C,S_E, 0,0,0,0,0,0,0);

    float ruleY = L.ruleY;
    col += sui3Rule(P, R, ruleY, pad, T);

    // ---- specimen column (left 58%) ----------------------------------------
    //
    // VERTICAL LAYOUT IS BAND-RELATIVE, NOT RAW PIXELS. Drawing strokes and
    // glyphs in pixels is correct and is what survives an extent change, but
    // using the published control_height (28 px) raw for LAYOUT overflowed a
    // 360-px-tall canvas and cut the primitives grid off entirely on the first
    // 640x360 capture. The published metrics still drive the layout -- that is
    // what makes this station load-bearing -- but they are clamped into the
    // band that actually exists, and the pad absorbs the remainder.
    // All of these now come from saLayout(). The reasoning that produced them
    // lives in layout.hlsli; the important property is that the events pass
    // computes the identical numbers, so a click cannot land off a control.
    float bodyTop = L.bodyTop;
    float colL = L.colL;
    float colR = L.colR;
    bool  showGrid = L.showGrid;
    float capH = L.capH;
    float ch = L.ch, cg = L.cg, mH = L.mH;

    float4 rPad = L.rPad;
    col += T.dim * sui3Text(P, float2(colL, bodyTop), sS, S_P,S_A,S_D,0,0,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rPad) > 0.5 || sui3Frame(P, rPad) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rPad));
        col += sui3Pad(P, rPad, t3.xy, T);
    }
    // live readout, attached to the thing it describes
    col += T.ink * sui3Fixed(P, float2(colR - pad - sui3FixedWidth(sB,2) * 2.0 - 8.0 * sB,
                                       bodyTop), sB, t3.x, 2);
    col += T.accent * sui3Fixed(P, float2(colR - pad - sui3FixedWidth(sB,2),
                                          bodyTop), sB, t3.y, 2);

    // rail specimen
    float4 rRail = L.rRail;
    float railY = rRail.y;
    col += T.dim * sui3Text(P, float2(colL, railY - 11.0 * sB), sS,
        S_R,S_A,S_I,S_L,0,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rRail) > 0.5 || sui3Frame(P, rRail) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rRail));
        col += sui3Rail(P, rRail, t2.w, T);
    }
    col += T.ink * sui3Fixed(P, float2(rRail.z + 8.0 * sB, railY + ch * 0.5 - 5.0 * sB), sB, t2.w, 2);

    // toggle + bank row
    float rowY = L.rowY;
    float tw = ch * 2.6;
    float4 rTog = L.rTog;
    col += T.dim * sui3Text(P, float2(colL, rowY - 11.0 * sB), sS,
        S_S,S_T,S_A,S_T,S_E,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rTog) > 0.5 || sui3Frame(P, rTog) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rTog));
        col += sui3Toggle(P, rTog, t3.z > 0.5, T);
    }
    col += (t3.z > 0.5 ? T.accent : T.dim)
         * sui3Text(P, float2(colL + 7.0 * sB, rowY + ch * 0.5 - 5.0 * sB), sB,
                    S_O, t3.z > 0.5 ? S_N : S_F, t3.z > 0.5 ? 0 : S_F,
                    0,0,0,0,0,0,0,0,0);

    // bank of four cells, with its own caption and a divider so the toggle and
    // the bank do not read as one row of five controls
    int bank = (int)round(clamp(t3.w, 0.0, 3.0));
    // Must clear the STATE caption, not just the toggle box: at a small ch the
    // two captions ran together and printed "STATEBANK".
    float bx0 = L.bx0;
    col += T.rule * 0.6 * sui3HairAt(P.x, colL + tw + cg * 1.5)
         * step(rowY - 11.0 * sB, P.y) * step(P.y, rowY + ch);
    col += T.dim * sui3Text(P, float2(bx0, rowY - 11.0 * sB), sS,
        S_B,S_A,S_N,S_K,0,0,0,0,0,0,0,0);
    float bw = L.bw;
    [loop] for (int b = 0; b < 4; ++b) {
        float4 rc = saBankCell(L, b);
        float x = rc.x;
        if (sui3RectIn(P, rc) > 0.5 || sui3Frame(P, rc) > 0.0) {
            col = lerp(col, float3(0,0,0), sui3RectIn(P, rc));
            col += sui3BankCell(P, rc, b == bank, T);
        }
        col += (b == bank ? T.accent : T.dim)
             * sui3Digits(P, float2(x + bw * 0.5 - 3.0 * sB, rowY + ch * 0.5 - 5.0 * sB), sB, b, 1);
    }

    // meters
    float mY = L.mY;
    float mw = L.mw;
    col += T.dim * sui3Text(P, float2(colL, mY - 11.0 * sB), sS,
        S_M,S_E,S_T,S_E,S_R,S_S,0,0,0,0,0,0);
    [loop] for (int m = 0; m < 6; ++m) {
        float x = colL + (float)m * (mw + cg);
        float4 rm = float4(x, mY, x + mw, mY + mH);
        float v = frac(t2.w + (float)m * 0.17);
        if (sui3RectIn(P, rm) > 0.5 || sui3Frame(P, rm) > 0.0) {
            col = lerp(col, float3(0,0,0), sui3RectIn(P, rm));
            col += sui3Meter(P, rm, v, min(1.0, v + 0.12), T);
        }
    }
    // A 20px meter cannot carry its own digits, so the BANK carries them: the
    // seed the six lanes are derived from, printed once at the bank's right.
    // Leaving it off made METERS the one control on the sheet you could not
    // read a number off, which is the exact failure the kit forbids elsewhere.
    col += T.ink * sui3Fixed(P, float2(colL + 6.0 * (mw + cg) + cg,
                                       mY + mH * 0.5 - 5.5 * sB), sB, t2.w, 2);

    // ---- published-value table (right 42%) ---------------------------------
    float tx = R.x * 0.615;
    float tvx = R.x - pad;                 // right edge for the value column
    float ty = bodyTop;
    float lh = 13.0 * sB;

    col += T.dim * sui3Text(P, float2(tx, ty), sS,
        S_P,S_U,S_B,S_L,S_I,S_S,S_H,S_E,S_D,0,0,0);
    ty += lh + 4.0 * sB;

    float4 rTab = float4(tx - 6.0 * sB, ty - 4.0 * sB, R.x - pad + 6.0 * sB, ty + lh * 11.0);
    col += T.rule * sui3Frame(P, rTab);
    col += T.mid * sui3Brackets(P, rTab, 12.0) * 0.6;

    // Every row below prints a value read back from the SAME buffer the control
    // outputs are taken from, so the table cannot drift from what is published.
    float vw = sui3FixedWidth(sB, 2);

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_T,S_I,S_T,S_L,S_E,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(tvx - vw, ty), sB, t0.x, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_S,S_E,S_C,S_T,S_N,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(tvx - vw, ty), sB, t0.y, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_B,S_O,S_D,S_Y,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(tvx - vw, ty), sB, t0.z, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_E,S_X,S_P,S_O,S_S,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(tvx - vw, ty), sB, t0.w, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_P,S_A,S_D,S_SP,S_P,S_X,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(tvx - vw, ty), sB, t1.x, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_G,S_A,S_P,0,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(tvx - vw, ty), sB, t1.y, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_C,S_T,S_L,S_SP,S_H,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(tvx - vw, ty), sB, t1.z, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_C,S_T,S_L,S_SP,S_G,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(tvx - vw, ty), sB, t1.w, 2); ty += lh;

    // the accent row prints IN the accent, because this row IS the accent
    float accentRowY = ty;
    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_A,S_C,S_C,S_N,S_T,0,0,0,0,0,0,0);
    col += T.accent * sui3Fixed(P, float2(tvx - vw, ty), sB, t2.x, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_P,S_A,S_D,S_SP,S_Y,0,0,0,0,0,0,0);
    col += T.accent * sui3Fixed(P, float2(tvx - vw, ty), sB, t3.y, 2); ty += lh;

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_B,S_A,S_N,S_K,0,0,0,0,0,0,0,0);
    col += T.accent * sui3Digits(P, float2(tvx - sui3TextWidth(1, sB), ty), sB, bank, 1);

    // Accent CHIP, inline on the ACCNT row. Two earlier placements failed: a
    // full-width bar below the table became the largest element on the sheet,
    // contradicting the very "one sparingly used accent" contract this station
    // publishes; moving it under the table then put it where the primitives grid
    // paints, so it vanished entirely at 640x360. Inline next to the value it
    // names is both restrained and unoccluded.
    float chipH = 8.0 * sB;
    float4 rSw = float4(tx + sui3TextWidth(6, sB), accentRowY + 1.0 * sB,
                        tx + sui3TextWidth(6, sB) + chipH * 2.0, accentRowY + 1.0 * sB + chipH);
    col = lerp(col, float3(0, 0, 0), sui3RectIn(P, rSw));
    col += T.accent * sui3RectIn(P, rSw) * 0.92;
    col += T.rule * sui3Frame(P, rSw);

    // ---- primitive reference grid (lower half) -----------------------------
    // The gallery earns its place by being the authority's own proof: each cell
    // draws one v3 primitive at the CURRENT published theme, so changing a
    // theme value visibly retunes the reference itself.
    // Derived from the specimen column's actual bottom, not a fixed fraction:
    // a fraction put the PRIMITIVES caption straight through the meters.
    float gTop = max(L.gTop, mY + mH + 30.0 * sB);
    if (showGrid) {
    col += sui3Rule(P, R, gTop - 26.0 * sB, pad, T);
    col += T.dim * sui3Text(P, float2(pad, gTop - 19.0 * sB), sS,
        S_P,S_R,S_I,S_M,S_I,S_T,S_I,S_V,S_E,S_S,0,0);

    float gCols = 4.0;
    float gRows = 2.0;
    float gW = (R.x - pad * 2.0 - cg * (gCols - 1.0)) / gCols;
    float gH = (R.y - pad - gTop - cg * (gRows - 1.0)) / gRows;

    [loop] for (int gi = 0; gi < 8; ++gi) {
        float gx = pad + (float)(gi % 4) * (gW + cg);
        float gy = gTop + (float)(gi / 4) * (gH + cg);
        float4 rg = float4(gx, gy, gx + gW, gy + gH);
        float4 inner = float4(rg.x + 10.0 * sB, rg.y + 16.0 * sB,
                              rg.z - 10.0 * sB, rg.w - 10.0 * sB);
        float2 ic = (inner.xy + inner.zw) * 0.5;

        col = lerp(col, float3(0, 0, 0), sui3RectIn(P, rg));
        col += T.well * 0.7 * sui3RectIn(P, rg);
        col += T.rule * sui3Frame(P, rg);
        col += T.mid * sui3Brackets(P, rg, 10.0) * 0.5;

        if (gi == 0) {          // HAIRLINE
            col += T.dim * sui3Text(P, float2(rg.x + 6.0 * sB, rg.y + 4.0 * sB), sB,
                S_H,S_A,S_I,S_R,0,0,0,0,0,0,0,0);
            col += T.ink * sui3Line(P, float2(inner.x, ic.y), float2(inner.z, ic.y), 1.0);
        } else if (gi == 1) {   // FRAME
            col += T.dim * sui3Text(P, float2(rg.x + 6.0 * sB, rg.y + 4.0 * sB), sB,
                S_F,S_R,S_A,S_M,S_E,0,0,0,0,0,0,0);
            col += T.ink * sui3Frame(P, float4(ic.x - gW * 0.22, ic.y - gH * 0.18,
                                               ic.x + gW * 0.22, ic.y + gH * 0.18));
        } else if (gi == 2) {   // BRACKETS
            col += T.dim * sui3Text(P, float2(rg.x + 6.0 * sB, rg.y + 4.0 * sB), sB,
                S_B,S_R,S_K,S_T,S_S,0,0,0,0,0,0,0);
            col += T.ink * sui3Brackets(P, float4(ic.x - gW * 0.22, ic.y - gH * 0.18,
                                                  ic.x + gW * 0.22, ic.y + gH * 0.18), 14.0);
        } else if (gi == 3) {   // GRATICULE
            col += T.dim * sui3Text(P, float2(rg.x + 6.0 * sB, rg.y + 4.0 * sB), sB,
                S_G,S_R,S_A,S_T,0,0,0,0,0,0,0,0);
            col += T.mid * 0.7 * sui3Graticule(P, inner, float2(6.0, 4.0));
        } else if (gi == 4) {   // RETICLE
            col += T.dim * sui3Text(P, float2(rg.x + 6.0 * sB, rg.y + 4.0 * sB), sB,
                S_R,S_E,S_T,S_I,S_C,S_L,S_E,0,0,0,0,0);
            col += T.ink * sui3Reticle(P, ic, 5.0, 22.0) * 0.9;
            col += T.accent * sui3Ring(P, ic, 8.5, 1.2);
        } else if (gi == 5) {   // TICKS
            col += T.dim * sui3Text(P, float2(rg.x + 6.0 * sB, rg.y + 4.0 * sB), sB,
                S_T,S_I,S_C,S_K,S_S,0,0,0,0,0,0,0);
            col += T.mid * sui3Ticks(P, inner, 16.0, 8.0, 0);
            col += T.dim * sui3Ticks(P, inner, 8.0, 6.0, 1);
        } else if (gi == 6) {   // EDGE READOUT
            col += T.dim * sui3Text(P, float2(rg.x + 6.0 * sB, rg.y + 4.0 * sB), sB,
                S_E,S_D,S_G,S_E,0,0,0,0,0,0,0,0);
            float2 at = lerp(inner.xy, inner.zw, float2(saturate(t2.w), 0.42));
            col += T.rule * 0.5 * sui3Frame(P, inner);
            col += T.accent * sui3EdgeReadout(P, inner, at, 5.0) * 0.9;
            col += T.ink * sui3Disc(P, at, 2.0);
        } else {                // REGISTRATION
            col += T.dim * sui3Text(P, float2(rg.x + 6.0 * sB, rg.y + 4.0 * sB), sB,
                S_R,S_E,S_G,0,0,0,0,0,0,0,0,0);
            float2 lc = P - inner.xy;
            float2 lR = inner.zw - inner.xy;
            if (lc.x >= 0.0 && lc.y >= 0.0 && lc.x <= lR.x && lc.y <= lR.y) {
                col += T.mid * sui3Registration(lc, lR, 16.0);
            }
        }
    }

    }   // showGrid

    // ---- frame and registration --------------------------------------------
    col += T.rule * sui3Frame(P, float4(pad * 0.5, pad * 0.5, R.x - pad * 0.5, R.y - pad * 0.5)) * 0.7;
    col += T.mid * sui3Registration(P, R, 22.0) * 0.85;

    Out[tid.xy] = float4(saturate(col), 1.0);
}
