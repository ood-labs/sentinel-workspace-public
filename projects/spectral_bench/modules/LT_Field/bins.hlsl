// LT_Field / bins.hlsl — the acceleration layer.
//
// A beam is a SPARSE ONE-DIMENSIONAL MARK: it covers a few thousand pixels out of nine hundred
// thousand. A per-pixel loop over every traced segment is therefore a million distance tests per
// pixel for an image that is mostly empty, which is the wrong cost model by two orders of
// magnitude.
//
// So each 16-pixel tile collects the segments that could possibly touch it, once, and the
// renderer tests only its own tile's list. Cost becomes proportional to the ink drawn rather
// than to the screen area it might occupy.
//
// GATHER, NOT SCATTER: one thread owns one tile and walks the segments. No atomics, no clear
// pass for the dependency scheduler to misplace, and the result is bit-identical every cook.
#include "../_shared/bench.hlsli"
StructuredBuffer<PathSeg> Paths : register(t0);
RWStructuredBuffer<uint>  Bins  : register(u0);
#include "segwidth.hlsli"

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint tile = DTid.x;
    if (tile >= (uint)LT_TILES) return;

    uint base = tile * (uint)LT_BIN_STRIDE;
    uint tx = tile % (uint)LT_TILES_X;
    uint ty = tile / (uint)LT_TILES_X;
    float2 t0 = float2((float)tx, (float)ty) * (float)LT_TILE;
    float2 t1 = t0 + (float)LT_TILE;

    PathSeg H = Paths[LT_PATH_HDR];
    uint liveSegs = (uint)clamp(H.a.x, 0.0, (float)LT_PATH_TOTAL);
    uint raysPer  = (uint)clamp(H.evt,   1.0, (float)LT_MAX_RAY);
    uint nRay     = (uint)clamp(H.b.x,   1.0, (float)LT_MAX_RAY);
    uint nWave    = (uint)clamp(H.b.y,   1.0, (float)LT_MAX_WAVE);
    uint nBranch  = (uint)clamp(H.wl,    1.0, (float)LT_BRANCH);
    uint stride   = (uint)clamp(H.depth, 1.0, (float)LT_MAX_SEG);

    float ppb = ltPxPerBench(view_zoom);
    float coreW = ltCoreW(ppb, beam_width, H.dev, raysPer);

    float2 res = float2((float)FIELD_W, (float)FIELD_H);
    uint cnt = 0u;
    uint over = 0u;

    [loop] for (uint i = 0u; i < liveSegs; ++i)
    {
        PathSeg g = Paths[i];
        if (g.power <= 1e-4) continue;

        // This segment's OWN reach, not a global worst case.
        float localW = ltSegWidth(g, coreW, ppb, nRay, nWave, nBranch, stride);
        float rad = ltSegReach(localW, coreW, haze);

        float2 a = ltFieldToPix(g.a, view_center, view_zoom, res);
        float2 b = ltFieldToPix(g.b, view_center, view_zoom, res);
        float2 lo = min(a, b) - rad, hi = max(a, b) + rad;
        if (hi.x < t0.x || lo.x > t1.x || hi.y < t0.y || lo.y > t1.y) continue;

        if (cnt < (uint)LT_BIN_CAP) { Bins[base + 2u + cnt] = i; cnt++; }
        else over = 1u;
    }

    Bins[base]      = cnt;
    // A silently truncated tile would just quietly drop beams. The renderer has an Occupancy view
    // that draws this, so a bench dense enough to overflow says so instead of looking dim.
    Bins[base + 1u] = over;
}
