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
    bool   showGrid, showSub;
    float  gTop;
};

// A caption is a fixed number of PIXELS tall sitting in a NORMALIZED gap, so the
// gap shrinks with the panel while the caption does not. Callers pass the real
// gap; a caption that cannot fit is dropped rather than printed across the
// control above it. Same rule as modules/motion_console/layout.hlsli.
//
// `want` is the scale the caption ASKS for. Every section caption here renders
// at the section scale, while the old boolean test and its matching y-offset
// were both passed the BODY scale -- so at section 2 / body 1 the glyphs were
// twice the height the layout had reserved and RAIL, STATE, BANK and METERS
// each printed through the control above them. A fit test measuring a
// different scale than the draw is not a fit test.
//
// Returning a SCALE rather than a yes/no is the other half. Dropping a caption
// is the correct answer only when even 1x cannot fit; when the gap is merely
// too small for the requested size, shrinking keeps the label. That is the same
// give-back the header already does with the title, and it means raising
// Section Scale can never silently delete the control captions.
//
// 0 means the gap cannot hold a caption at all: do not draw.
float saCapScale(float gapPx, float want) {
    float fit = floor((gapPx - 3.0) / 13.0);
    return min(max(1.0, floor(want)), max(fit, 0.0));
}

// The baseline offset above a control for a caption drawn at `scale`.
float saCapOffset(float scale) { return 13.0 * scale + 2.0; }

// `titleScale`/`sectionScale` are the published type scales; the four layout
// metrics are the published pixel metrics. See render.hlsl for why the boxes
// are NOT multiplied by the glyph scale.
SaLayout saLayout(float2 R, float titleScale, float sectionScale, float bodyScale,
                  float outerPad, float sectionGap, float ctlH, float ctlG) {
    SaLayout L;
    L.R  = R;
    // Scale from the SMALLER axis ratio, not from height alone. Height alone
    // picks 2x on a canvas only 1.25x bigger and on a wide-and-short dock puts
    // giant glyphs in bands too thin to hold them. Same fix as
    // modules/motion_console/render.hlsl; see phase doc Amendment 3.
    float kS = min(R.x / 1280.0, R.y / 720.0);
    float extentStep = kS >= 2.6 ? 3.0 : kS >= 1.7 ? 2.0 : 1.0;
    // bodyScale was published, printed in the readout table, and then never
    // reached this function -- the one metric the LIVE THEME SOURCE did not
    // apply to itself. It multiplies the extent step, so the extent still sets
    // the floor and the operator can only ever ask for more.
    // Glyph scales are INTEGER (the face is a bitmap), so all three of these
    // quantise: 1.8 is 1x, 2.0 is 2x. That is why the readout prints the
    // requested value while the sheet steps.
    L.sB = extentStep * max(1.0, floor(bodyScale));
    L.sS = extentStep * max(1.0, floor(sectionScale));

    // THE HOST'S RECTS, verbatim. They come first now, because the sheet's left
    // column and outer frame are derived FROM them.
    L.rPad  = saPx(UI_RECT_PAD,    R);
    L.rRail = saPx(UI_RECT_RAIL,   R);
    L.rTog  = saPx(UI_RECT_TOGGLE, R);
    float4 rBank = saPx(UI_RECT_BANK, R);

    // outer_padding is PUBLISHED IN PIXELS, so it is spent in pixels. It used to
    // be multiplied by the body glyph scale, which made a published 36px metric
    // draw a 72px inset -- the same class of defect as body_scale never reaching
    // this function: the live theme source not applying its own published value
    // to itself. It tracks the extent step, which is the thing that actually
    // changes pixel density, and not the operator's type-scale request.
    //
    // The clamp is the important half. The four control rects are STATIC
    // NORMALIZED values in the manifest; they cannot move when a padding slider
    // does. With padding at 36 and body scale at 2 the frame and the whole text
    // column sat 50px right of the control column, so the pad, rail, toggle and
    // bank hung off the left of the sheet. The rects cannot give way, so the
    // sheet does: the frame is held clear of the control column at every
    // padding setting, and the text column simply IS the control column.
    L.pad     = min(outerPad * extentStep, max(8.0, 2.0 * L.rPad.x - 10.0));
    L.headY   = L.pad + 2.0 * L.sB;
    L.colL    = L.rPad.x;
    L.colR    = R.x * 0.575;

    L.showGrid = (R.y >= 520.0);
    float gTopPlanned = L.showGrid ? (R.y * 0.60) : (R.y - L.pad);
    // Section captions render at the SECTION scale, so the space reserved for
    // them is measured at that scale too.
    L.capH = 11.0 * L.sS;
    L.cg   = max(ctlG, 2.0);

    // TITLE SCALE IS COMPUTED AFTER THE RECTS, because the header has to fit in
    // the space above the first control and that space is normalized while the
    // header is in pixels. At 640x360 the pad's top edge is 43px down and the
    // published 2x title plus its subtitle needed more than that, so the title
    // was drawn straight through the pad frame.
    //
    // `titleScale` stays the ceiling, never the floor: the published metric is
    // what the operator asked for, and this only ever gives back less when the
    // panel cannot hold it. The subtitle is surrendered before the title shrinks.
    float wantT = L.sB * max(1.0, floor(titleScale));
    float under = sectionGap * L.sB;
    float withSub = L.rPad.y - L.headY - 14.0 * L.sB - under;
    float t1 = floor(withSub / 13.0);
    if (t1 >= L.sB) {
        L.showSub = true;
        L.sT = min(t1, wantT);
    } else {
        L.showSub = false;
        float noSub = L.rPad.y - L.headY - 3.0 * L.sB - under;
        L.sT = clamp(floor(noSub / 13.0), 1.0, wantT);
    }
    L.ruleY   = L.headY + 13.0 * L.sT + (L.showSub ? 14.0 : 3.0) * L.sB;
    L.bodyTop = L.ruleY + under;

    L.ch   = L.rTog.w - L.rTog.y;
    L.rowY = L.rTog.y;
    L.bx0  = rBank.x;
    L.bw   = ((rBank.z - rBank.x) - L.cg * 3.0) / 4.0;

    L.mH = L.ch * 1.15;
    // Room for a METERS caption at the section scale, plus the control gap.
    L.mY = rBank.w + L.cg + saCapOffset(max(1.0, floor(L.sS)));
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
