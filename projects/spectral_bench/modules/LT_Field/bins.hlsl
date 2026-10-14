// LT_Field / bins.hlsl — the acceleration layer.
//
// A beam is a SPARSE ONE-DIMENSIONAL MARK: it covers a few thousand pixels out of nine hundred
// thousand. A per-pixel loop over every traced segment is therefore a million distance tests per
// pixel for an image that is mostly empty, which is the wrong cost model by two orders of
// magnitude.
//
// So each 32-pixel tile collects the segments that could possibly touch it, once, and the
// renderer tests only its own tile's list. Cost becomes proportional to the ink drawn rather
// than to the screen area it might occupy.
//
// GATHER, NOT SCATTER: one GROUP owns one tile. Its 64 threads split the segment list into
// contiguous runs, count their hits, and a prefix over those counts tells each run where its
// hits go — so the list comes out in segment order, exactly as if one thread had walked it. No
// global atomics, no clear pass for the dependency scheduler to misplace, and the result is
// bit-identical every cook. One thread per tile was the same list, but two thousand serial walks
// over every segment left the GPU nearly empty for six milliseconds.
//
// A tile walks its ROW's shortlist (rows.hlsl) rather than every segment; the shortlist is in
// segment order and holds everything that reaches the row, so the tile's list is unchanged.
// Each segment is tested against its OWN reach, not a global worst case (segs.hlsl).
#include "../_shared/bench.hlsli"
#include "view.hlsli"
StructuredBuffer<SegPx>   Segs  : register(t0);
StructuredBuffer<uint>    Rows  : register(t1);
RWStructuredBuffer<uint>  Bins  : register(u0);

groupshared uint gsHits[64];

[numthreads(64, 1, 1)]
void main(uint3 Gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    // Dispatched with exactly one group per tile.
    uint tile = min(Gid.x, (uint)LT_TILES - 1u);

    uint base = tile * (uint)LT_BIN_STRIDE;
    uint tx = tile % (uint)LT_TILES_X;
    uint ty = tile / (uint)LT_TILES_X;
    float2 t0 = float2((float)tx, (float)ty) * (float)LT_TILE;
    float2 t1 = t0 + (float)LT_TILE;

    uint row = ty * (uint)LT_ROW_STRIDE;
    uint rowCnt = Rows[row];
    uint per = (rowCnt + 63u) / 64u;
    uint j0 = min(gi * per, rowCnt);
    uint j1 = min(j0 + per, rowCnt);

    uint mine = 0u;
    [loop] for (uint j = j0; j < j1; ++j)
        if (ltSegInTile(Segs[Rows[row + 1u + j]], t0, t1)) mine++;
    gsHits[gi] = mine;
    GroupMemoryBarrierWithGroupSync();

    uint at = 0u, total = 0u;
    [loop] for (uint k = 0u; k < 64u; ++k)
    {
        uint h = gsHits[k];
        if (k < gi) at += h;
        total += h;
    }

    [loop] for (uint j2 = j0; j2 < j1 && at < (uint)LT_BIN_CAP; ++j2)
    {
        uint i = Rows[row + 1u + j2];
        if (ltSegInTile(Segs[i], t0, t1)) { Bins[base + 2u + at] = i; at++; }
    }

    if (gi == 0u)
    {
        Bins[base] = min(total, (uint)LT_BIN_CAP);
        // A silently truncated tile would just quietly drop beams. The renderer has an Occupancy
        // view that draws this, so a bench dense enough to overflow says so instead of looking dim.
        Bins[base + 1u] = (total > (uint)LT_BIN_CAP) ? 1u : 0u;
    }
}
