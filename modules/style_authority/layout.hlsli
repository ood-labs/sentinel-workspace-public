#ifndef STYLE_AUTHORITY_LAYOUT_HLSLI
#define STYLE_AUTHORITY_LAYOUT_HLSLI

// Shared layout for Style Authority.
//
// THE FOUR CONTROL RECTS ARE NOT COMPUTED HERE. They come from
// `_ui.generated.hlsli`, which `tools/module-ui.ps1 generate` compiles from the
// `viewport.controls` block in manifest.yaml -- the same rects the HOST uses for
// hit-testing. Drawing from the host's own numbers is what makes "the click
// landed where I aimed" true by construction instead of by careful maintenance,
// and `module-ui.ps1 validate` fails the build if the generated file drifts
// from the manifest.
//
// Everything else -- captions, the meters strip, the primitives grid -- is
// derived from those rects and from the published metrics, and stays here.
//
// Pixel space throughout, matching the kit.
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "_ui.generated.hlsli"

// Normalized manifest rect -> pixels.
float4 saPx(float4 n, float2 R) { return float4(n.x * R.x, n.y * R.y, n.z * R.x, n.w * R.y); }

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
    L.capH = 11.0 * L.sB;
    L.cg   = max(ctlG, 2.0);

    // THE HOST'S RECTS, verbatim.
    L.rPad  = saPx(UI_RECT_PAD,    R);
    L.rRail = saPx(UI_RECT_RAIL,   R);
    L.rTog  = saPx(UI_RECT_TOGGLE, R);
    float4 rBank = saPx(UI_RECT_BANK, R);

    L.ch   = L.rTog.w - L.rTog.y;
    L.rowY = L.rTog.y;
    L.bx0  = rBank.x;
    L.bw   = ((rBank.z - rBank.x) - L.cg * 3.0) / 4.0;

    L.mH = L.ch * 1.15;
    L.mY = rBank.w + L.cg + 11.0 * L.sB;
    L.mw = L.ch * 0.72;

    L.gTop = gTopPlanned;
    return L;
}

// One cell of the bank. The bank is a single host slider spanning four cells,
// so a click at a cell's centre resolves to that cell's index; the cells are a
// drawing of the slider's discrete positions, not four separate controls.
float4 saBankCell(SaLayout L, int i) {
    float x = L.bx0 + (float)i * (L.bw + L.cg);
    return float4(x, L.rowY, x + L.bw, L.rowY + L.ch);
}

#endif
