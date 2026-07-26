#ifndef STYLE_AUTHORITY_LAYOUT_HLSLI
#define STYLE_AUTHORITY_LAYOUT_HLSLI

// Shared layout for Style Authority.
//
// WHY THIS FILE EXISTS. The render pass draws the pad, toggle and bank; the
// events pass has to hit-test the same three rects. If each computed its own
// geometry they would drift the moment a layout constant changed, and the
// symptom -- a click landing a few pixels off the control it visibly hit -- is
// the single most confusing bug class in an authored UI. One function, two
// consumers, no possibility of disagreement.
//
// Both passes get the same numbers because the published theme is a straight
// copy of the parameters: `state.hlsl` writes params into the Theme buffer, so
// the events pass reading params and the render pass reading the buffer are
// reading the same values one frame apart at worst.
//
// Pixel space throughout, matching the kit.
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"

struct SaLayout {
    float2 R;
    float  sB, sT, sS;      // glyph scales: body, title, section
    float  pad, headY, ruleY, bodyTop;
    float  colL, colR;
    float  capH, ch, cg, mH;
    float4 rPad, rRail, rTog;
    float  rowY, bx0, bw;   // bank origin and cell width
    float  mY, mw;
    bool   showGrid;
    float  gTop;
};

// `titleScale`/`sectionScale` are the published type scales; the four layout
// metrics are the published pixel metrics. See render.hlsl for why the boxes
// are NOT multiplied by the glyph scale.
SaLayout saLayout(float2 R, float titleScale, float sectionScale,
                  float outerPad, float sectionGap, float ctlH, float ctlG) {
    SaLayout L;
    L.R  = R;
    L.sB = (R.y >= 800.0) ? 2.0 : 1.0;
    L.sT = L.sB * max(1.0, floor(titleScale));
    L.sS = L.sB * max(1.0, floor(sectionScale));

    L.pad     = outerPad * L.sB;
    L.headY   = L.pad + 2.0 * L.sB;
    L.ruleY   = L.headY + 13.0 * L.sT + 14.0 * L.sB;
    L.bodyTop = L.ruleY + sectionGap * L.sB;
    L.colL    = L.pad;
    L.colR    = R.x * 0.575;

    L.showGrid = (R.y >= 520.0);
    float gTopPlanned = L.showGrid ? (R.y * 0.60) : (R.y - L.pad);
    float band = max(gTopPlanned - 30.0 * L.sB - L.bodyTop, 60.0);
    L.capH = 11.0 * L.sB;

    float wantCh  = max(ctlH, 8.0);
    float wantCg  = max(ctlG, 2.0);
    float wantPad = wantCh * 5.0;
    float wantM   = wantCh * 1.2;

    float textTotal = L.capH * 4.0;
    float boxAvail  = max(band - textTotal, 40.0);
    float boxWant   = wantPad + wantCh * 2.0 + wantM + wantCg * 3.0;
    float fit       = min(1.0, boxAvail / max(boxWant, 1.0));

    L.ch   = wantCh  * fit;
    L.cg   = wantCg  * fit;
    L.mH   = wantM   * fit;
    float padH = wantPad * fit;

    L.rPad = float4(L.colL, L.bodyTop + L.capH, L.colR - L.pad,
                    L.bodyTop + L.capH + padH);

    float railY = L.rPad.w + L.cg + 11.0 * L.sB;
    L.rRail = float4(L.colL, railY,
                     L.colR - L.pad - sui3FixedWidth(L.sB, 2) - 8.0 * L.sB,
                     railY + L.ch);

    L.rowY = L.rRail.w + L.cg + 11.0 * L.sB;
    float tw = L.ch * 2.6;
    L.rTog = float4(L.colL, L.rowY, L.colL + tw, L.rowY + L.ch);

    L.bx0 = L.colL + max(tw + L.cg * 3.0, sui3TextWidth(6, L.sS) + L.cg * 2.0);
    L.bw  = (L.colR - L.pad - L.bx0 - L.cg * 3.0) / 4.0;

    L.mY = L.rowY + L.ch + L.cg + 11.0 * L.sB;
    L.mw = L.ch * 0.72;

    L.gTop = gTopPlanned;
    return L;
}

float4 saBankCell(SaLayout L, int i) {
    float x = L.bx0 + (float)i * (L.bw + L.cg);
    return float4(x, L.rowY, x + L.bw, L.rowY + L.ch);
}

// Hit tests are FORGIVING by a few pixels. A 1px-hairline instrument draws
// exact boundaries, but a pointer is not exact; requiring a click inside the
// literal stroke makes a correct control feel broken.
bool saHit(float2 p, float4 r, float slopPx) {
    return p.x >= r.x - slopPx && p.x <= r.z + slopPx
        && p.y >= r.y - slopPx && p.y <= r.w + slopPx;
}

#endif
