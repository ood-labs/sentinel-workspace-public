// finish_layout.hlsli -- the ONE grid of BR_Finish's board, shared by the reducer (finish.hlsl), the
// samples (plate.hlsl) and the draw list (layout.hlsl), so what you see is what you hit. Output
// pixels throughout, scaled by the Interaction Lab kit's ui scale (ilCtx).
#ifndef FINISH_LAYOUT_HLSLI
#define FINISH_LAYOUT_HLSLI

#include "../_shared/ui/il_core.hlsli"

struct FinishLayout
{
    float2 res;
    float s;            // ui scale (1 at 1280 x 720)
    float4 head;        // the title strip
    float4 foot;        // the hint strip
    float2 origin;      // top-left of the grid
    float cell;         // square cell size (px)
    int cols, rows;
};

FinishLayout finishLayout(float2 res)
{
    FinishLayout L;
    L.res = res;
    L.s = ilCtx(res).s;
    L.head = float4(0.0, 0.0, res.x, ilSnap(36.0 * L.s));
    L.foot = float4(0.0, res.y - ilSnap(32.0 * L.s), res.x, res.y);
    float margin = 14.0 * L.s;
    float2 avail = float2(res.x - 2.0 * margin, L.foot.y - L.head.w - 2.0 * margin);
    int cands[4] = { 4, 6, 8, 12 };
    L.cols = 6; L.rows = 4; L.cell = 1.0;
    float best = -1.0;
    [unroll] for (int i = 0; i < 4; i++)
    {
        int c = cands[i];
        int r = (MAT_SLOTS + c - 1) / c;
        float cell = min(avail.x / (float)c, avail.y / (float)r);
        if (cell > best) { best = cell; L.cols = c; L.rows = r; }
    }
    L.cell = max(floor(best), 24.0);
    float2 grid = float2(L.cols, L.rows) * L.cell;
    L.origin = float2((res.x - grid.x) * 0.5, L.head.w + margin + (avail.y - grid.y) * 0.5);
    return L;
}

float4 finishCellRect(FinishLayout L, int i)
{
    int cx = i % L.cols, cy = i / L.cols;
    float2 o = L.origin + float2(cx, cy) * L.cell;
    return float4(o, o + L.cell);
}
// The sample's card: the cell less a gutter. A click anywhere in the cell still selects it.
float4 finishCardRect(FinishLayout L, int i) { return ilInset(finishCellRect(L, i), ilSnap(3.0 * L.s)); }

int finishCellAt(FinishLayout L, float2 px)
{
    float2 q = (px - L.origin) / L.cell;
    if (q.x < 0.0 || q.y < 0.0) return -1;
    int cx = (int)floor(q.x), cy = (int)floor(q.y);
    if (cx >= L.cols || cy >= L.rows) return -1;
    int i = cy * L.cols + cx;
    return (i < MAT_SLOTS) ? i : -1;
}

#endif
