// Light-list overflow, for the tile_overflow control outputs: tiles whose narrow candidates, or wide sources kept by
// sampling, exceeded the per-tile lists (those lights were dropped from that tile), and the most narrow and wide
// candidates any tile had.
#include "../_shared/fe_tiles.hlsli"

StructuredBuffer<uint> Tiles : register(t0);
RWStructuredBuffer<float4> Stats : register(u0);

groupshared uint gOverN, gOverB, gMaxN, gMaxB;

[numthreads(256, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    float2 res = _Resolution.x > 0.5 ? _Resolution.xy : float2(1280.0, 720.0);
    uint2 tiles = (uint2)ceil(res / (float)FE_TILE);
    tiles = min(tiles, uint2(FE_TILES_X_MAX, FE_TILES_Y_MAX));
    if (gi == 0u) { gOverN = 0u; gOverB = 0u; gMaxN = 0u; gMaxB = 0u; }
    GroupMemoryBarrierWithGroupSync();
    for (uint t = gi; t < tiles.x * tiles.y; t += 256u)
    {
        uint tile = (t / tiles.x) * FE_TILES_X_MAX + (t % tiles.x);
        uint raw = Tiles[tile * FE_TILE_STRIDE + FE_TILE_RAW];
        uint n = raw & 0xFFFFu, b = raw >> 16;
        if (n > FE_TILE_MAX_NARROW) InterlockedAdd(gOverN, 1u);
        if (Tiles[tile * FE_TILE_STRIDE + FE_TILE_WANT] > FE_TILE_MAX_BROAD) InterlockedAdd(gOverB, 1u);
        InterlockedMax(gMaxN, n);
        InterlockedMax(gMaxB, b);
    }
    GroupMemoryBarrierWithGroupSync();
    if (gi == 0u) Stats[0] = float4((float)gOverN, (float)gOverB, (float)gMaxN, (float)gMaxB);
}
