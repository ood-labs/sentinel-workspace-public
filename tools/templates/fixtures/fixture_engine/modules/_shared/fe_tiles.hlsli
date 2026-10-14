// Per-tile light lists shared by the FE_Renderer passes. Tile = 16 x 16 full-resolution pixels
// (= 8 x 8 at half resolution). Tiles[tile * FE_TILE_STRIDE] = narrow count | broad count << 16, then the
// narrow source indices, then (at +1 + FE_TILE_MAX_NARROW) the broad entries. Indices address Sources[3k].
// A broad entry is its source index | its keep probability q << 17 (q / 32767): where wide sources outnumber a tile's
// list, each is kept with one probability, from the most candidates any tile that listed it had last frame, and
// weighted by its inverse (feBroadEntry), so the light stays whole on average and every tile keeps or drops a source
// together (each source draws one fixed random number). Candidates count dark sources too, so the look never moves a
// probability and a lit source does not blink in and out as other sources change.
// After the lists: the uncapped counts (FE_TILE_RAW), so the tile_stats pass can count tiles that dropped lights, and
// the wide sources sampling kept before the list cap (FE_TILE_WANT). After every tile, per source slot, in two halves
// written on alternate frames: the most candidates of a tile that listed it (FE_BROAD_CROWD, frame tag << 24 | count).
#ifndef FE_TILES_HLSLI
#define FE_TILES_HLSLI

#define FE_TILE 16u
#define FE_TILES_X_MAX 120u        // 1920 / 16
#define FE_TILES_Y_MAX 68u         // ceil(1080 / 16)
#define FE_TILE_MAX_NARROW 448u
#define FE_TILE_MAX_BROAD 128u
#define FE_TILE_STRIDE 579u        // 1 + 448 + 128 + raw counts, sampled count
#define FE_TILE_RAW 577u
#define FE_TILE_WANT 578u
#define FE_BROAD_TARGET 108.0      // sampled wide sources aimed for per tile, a margin under FE_TILE_MAX_BROAD
#define FE_SOURCE_SLOTS 131072u    // FE_N_MAX x FE_CELLS_CAP
#define FE_BROAD_CROWD (FE_TILES_X_MAX * FE_TILES_Y_MAX * FE_TILE_STRIDE)

// A broad entry: (source index, weight 1 / keep probability as float bits).
uint2 feBroadEntry(uint entry)
{
    uint q = max(entry >> 17, 1u);
    return uint2(entry & 0x1FFFFu, asuint(32767.0 / (float)q));
}
#define FE_WASH_RANGE 16.0
#define FE_BEAM_REACH 40.0

// Where a beam ends: the deck (y = 0) or its reach.
float feBeamReach(float3 p, float3 a)
{
    return a.y < -1e-3 ? min(FE_BEAM_REACH, p.y / -a.y) : FE_BEAM_REACH;
}

#endif
