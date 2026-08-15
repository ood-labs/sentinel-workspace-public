// FM_Colony / grid.hlsl — who was where, bucketed, so nothing downstream has to ask everybody.
//
// At 64 ants both consumers of "which ants are near this point" could simply walk the whole
// population, and both did. At 1024 neither can: the pheromone deposit is a per-texel gather, so
// walking the population there is 246 000 texels x 1024 ants = 252 M tests per cook, and the
// separation term is 1 M. This pass turns both into a 3x3 cell query.
//
// BUILT BY GATHER, NOT SCATTER. One thread per CELL, looping the population and keeping the ants
// that belong to it — rather than one thread per ANT atomically appending to its cell. The
// gather does more arithmetic and buys three things worth more than the arithmetic:
//
//   - no atomics, so the contents of a cell are in a deterministic order and two runs of the
//     same seed produce the same frame;
//   - no clear pass, and therefore no clear that the dependency scheduler is free to run AFTER
//     the accumulate it is supposed to precede;
//   - a cell that fills up truncates in index order instead of by whoever won the race.
//
// It reads `ants`, so it is scheduled after walk and walk reads what it wrote LAST cook. That is
// the same one-cook feedback the pheromone field has always run on.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWStructuredBuffer<FmCell> Grid : register(u0);
StructuredBuffer<FmAnt>    Ants : register(t1);
StructuredBuffer<FmRec>    PlanB : register(t2);

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint cell = DTid.x;
    if (cell >= FM_GRID_N) return;              // 9 groups of 64 covers 576; 16 threads idle

    FmRec arena = PlanB[FM_ARENA];
    float2 ahalf = fmArenaHalf(arena);

    int2 me = int2((int)(cell % FM_GRID_X), (int)(cell / FM_GRID_X));

    uint n = min((uint)ant_count, FM_MAX_ANTS);
    uint k = 0u;

    for (uint i = 0u; i < n; i++)
    {
        FmAnt a = Ants[i];
        // A dormant ant is a free slot, not an animal. It has no position worth reporting, it
        // must not push its neighbours around, and it must not lay scent — so it never enters
        // the grid and every consumer gets the right answer without knowing about dormancy.
        if (a.active < 0.5) continue;

        // A persistent buffer is not guaranteed to arrive zeroed and one non-finite position
        // would put an ant in every cell at once. Tested by magnitude so it catches infinity.
        if (!(dot(a.pos, a.pos) < 1e12)) continue;

        int2 c = fmGridCell(a.pos.xz, ahalf);
        if (c.x != me.x || c.y != me.y) continue;

        if (k >= FM_CELL_CAP) break;            // truncates in index order, deterministically

        FmCellAnt e;
        e.pos  = a.pos.xz;
        e.idx  = (float)i;
        e.task = a.task;
        e.load = a.load;
        e.size = a.size;
        e.fade = a.fade;
        Grid[cell].a[k] = e;
        k++;
    }

    Grid[cell].count = (float)k;
    Grid[cell].pad0 = 0.0;
    Grid[cell].pad1 = 0.0;
    Grid[cell].pad2 = 0.0;
}
