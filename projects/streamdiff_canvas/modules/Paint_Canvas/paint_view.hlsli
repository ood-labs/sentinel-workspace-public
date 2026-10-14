// Paint_Canvas / paint_view - the editor's view geometry, in output pixels, for everything that
// DRAWS it: view.hlsl (the canvas per pixel) and layout.hlsl (toolbar, frame, footer).
//
// A 32 px toolbar with the CLEAR button at its right end, and the 1080 x 1350 canvas fitted into
// the rest, panned and zoomed by paint_state[19] (pan in canvas uv, zoom, middle button).
// events.hlsl hit-tests exactly these formulas with its own copy, which is the interaction
// contract and stays byte-for-byte: change one, change both.
#ifndef PAINT_VIEW_HLSLI
#define PAINT_VIEW_HLSLI

static const float2 PC_CANVAS_PIXELS = float2(1080.0, 1350.0);
static const float PC_TOOLBAR_PX = 32.0;

// The CLEAR button (events.hlsl tests the same rect, normalized).
float4 pcClearRectPx(float2 res) { return float4(res.x - 68.0, 5.0, res.x - 8.0, 27.0); }

float pcFitScale(float2 res)
{
    float availableHeight = max(res.y - PC_TOOLBAR_PX, 1.0);
    return max(min(res.x / PC_CANVAS_PIXELS.x, availableHeight / PC_CANVAS_PIXELS.y), 0.0001);
}

float2 pcCenterPx(float2 res)
{
    float availableHeight = max(res.y - PC_TOOLBAR_PX, 1.0);
    return float2(res.x * 0.5, PC_TOOLBAR_PX + availableHeight * 0.5);
}

// Output pixel -> canvas uv, and back.
float2 pcPxToCanvas(float2 px, float2 res, float2 pan, float zoom)
{
    return (px - pcCenterPx(res)) / (PC_CANVAS_PIXELS * pcFitScale(res) * max(zoom, 0.01)) + 0.5 + pan;
}
float2 pcCanvasToPx(float2 uv, float2 res, float2 pan, float zoom)
{
    return (uv - 0.5 - pan) * PC_CANVAS_PIXELS * pcFitScale(res) * max(zoom, 0.01) + pcCenterPx(res);
}

// Where the canvas lies on screen (past the view's edges when zoomed in).
float4 pcCanvasRectPx(float2 res, float2 pan, float zoom)
{
    return float4(pcCanvasToPx(float2(0.0, 0.0), res, pan, zoom), pcCanvasToPx(float2(1.0, 1.0), res, pan, zoom));
}

// Screen pixels per canvas pixel: the zoom a painter reads (1.0 = 100 %).
float pcDisplayScale(float2 res, float zoom) { return pcFitScale(res) * max(zoom, 0.01); }

// The Depth and Mask outputs as thumbnails stacked in the right margin, each under a caption row -
// only when the canvas leaves a margin wide enough (never over the painting); false otherwise.
bool pcThumbs(float2 res, float2 pan, float zoom, out float4 depthR, out float4 maskR)
{
    float4 cr = pcCanvasRectPx(res, pan, zoom);
    float x0 = max(cr.z, 0.0) + 16.0;
    float capH = 24.0;
    float hRoom = 0.5 * (res.y - PC_TOOLBAR_PX - 2.0 * capH - 16.0);
    float w = min(min(res.x - 12.0 - x0, 200.0), hRoom * PC_CANVAS_PIXELS.x / PC_CANVAS_PIXELS.y);
    float h = w * PC_CANVAS_PIXELS.y / PC_CANVAS_PIXELS.x;
    float y0 = PC_TOOLBAR_PX + capH + 4.0;
    depthR = float4(x0, y0, x0 + w, y0 + h);
    maskR = float4(x0, depthR.w + capH, x0 + w, depthR.w + capH + h);
    return w >= 64.0;
}

#endif
