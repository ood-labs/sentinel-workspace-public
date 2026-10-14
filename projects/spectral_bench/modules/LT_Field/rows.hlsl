// LT_Field / rows.hlsl — the first cut of the binning: which segments reach each ROW of tiles.
//
// A tile only needs the segments whose footprint crosses its row, and most of the trace lies in a
// few rows. So each row compacts that shortlist once, and the sixty tiles along it each walk the
// shortlist instead of every traced segment. The row test is the vertical half of the tile test
// (ltSegInRow, view.hlsli), so a tile's final list is exactly the one a full walk would build,
// in the same order.
//
// One group per row of tiles; the 64 threads split the segments into contiguous runs and a prefix
// over their counts keeps segment order, as in bins.hlsl.
#include "../_shared/bench.hlsli"
#include "view.hlsli"
StructuredBuffer<PathSeg> Paths : register(t0);
StructuredBuffer<SegPx>   Segs  : register(t1);
RWStructuredBuffer<uint>  Rows  : register(u0);

groupshared uint gsHits[64];

[numthreads(64, 1, 1)]
void main(uint3 Gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    // Dispatched with exactly one group per row of tiles.
    uint ty = min(Gid.x, (uint)LT_TILES_Y - 1u);
    uint base = ty * (uint)LT_ROW_STRIDE;
    float y0 = (float)ty * (float)LT_TILE;
    float y1 = y0 + (float)LT_TILE;

    PathSeg H = Paths[LT_PATH_HDR];
    uint liveSegs = (uint)clamp(H.a.x, 0.0, (float)LT_PATH_TOTAL);
    uint per = (liveSegs + 63u) / 64u;
    uint j0 = min(gi * per, liveSegs);
    uint j1 = min(j0 + per, liveSegs);

    uint mine = 0u;
    [loop] for (uint i = j0; i < j1; ++i)
        if (ltSegInRow(Segs[i], y0, y1)) mine++;
    gsHits[gi] = mine;
    GroupMemoryBarrierWithGroupSync();

    uint at = 0u, total = 0u;
    [loop] for (uint k = 0u; k < 64u; ++k)
    {
        uint h = gsHits[k];
        if (k < gi) at += h;
        total += h;
    }

    [loop] for (uint i2 = j0; i2 < j1; ++i2)
        if (ltSegInRow(Segs[i2], y0, y1)) { Rows[base + 1u + at] = i2; at++; }

    if (gi == 0u) Rows[base] = total;
}
