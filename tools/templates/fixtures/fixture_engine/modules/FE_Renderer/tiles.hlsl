// Light culling, once per 16 x 16 screen tile: which narrow beams (or their reflections in the deck) can reach
// the tile's view cone, and which wide sources are near enough to matter. The full-resolution beam pass and the
// half-resolution haze/floor pass both read these lists, so neither repeats the test per pixel or per pass.
// Each wide source has one keep probability, from the tiles that listed it last frame: 1 while none of them held more
// than FE_BROAD_TARGET candidates, else FE_BROAD_TARGET / the most candidates, so no tile wants more than
// FE_BROAD_TARGET. Dark sources count as candidates, so the probability follows the rig and the camera and never the
// look. It is kept against its own fixed random number and carries the probability for the volume pass to weight it by;
// every tile keeps or drops it together, so there are no tile edges, and a lit source stays kept or dropped while the
// look changes.
#define GDTF_RENDER _Data2
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"
#include "../_shared/fe_tiles.hlsli"

StructuredBuffer<float4> Sources : register(t0);
StructuredBuffer<float4> Frame : register(t1);
RWStructuredBuffer<uint> Tiles : register(u0);

groupshared uint gN[FE_TILE_MAX_NARROW];
groupshared uint gB[FE_TILE_MAX_BROAD];
groupshared uint gNN, gNB, gNK, gNPrev;

// Raises a frame-tagged maximum in Tiles[i] to v (tag << 24 | value); an entry from another frame is replaced.
void raiseTagged(uint i, uint v, uint tag)
{
    uint was = Tiles[i];
    [loop] for (uint attempt = 0u; attempt < 8u; attempt++)
    {
        uint want = ((was >> 24) != tag || v > was) ? v : was;
        if (want == was) break;
        uint seen;
        InterlockedCompareExchange(Tiles[i], was, want, seen);
        if (seen == was) break;
        was = seen;
    }
}

// Last frame's value of a frame-tagged maximum, or 0 if it is this frame's.
uint lastTagged(uint i, uint tag)
{
    uint v = Tiles[i];
    return (v >> 24) != tag ? v & 16777215u : 0u;
}

// One fixed random number in [0, 1) per source slot.
float sourceRandom(uint k)
{
    uint h = k * 747796405u + 2891336453u;
    h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
    h = (h >> 22u) ^ h;
    return (float)(h >> 8) / 16777216.0;
}

bool sphereInCone(float3 c, float r, float3 ro, float3 dc, float tanA, float secA)
{
    float3 v = c - ro;
    if (dot(v, v) <= r * r) return true;
    float along = dot(v, dc);
    return along > -r && length(v - dc * along) < along * tanA + r * secA;
}

[numthreads(64, 1, 1)]
void main(uint3 gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    float2 res = _Resolution.x > 0.5 ? _Resolution.xy : float2(1280.0, 720.0);
    uint2 tiles = (uint2)ceil(res / (float)FE_TILE);
    uint tile = gid.y * FE_TILES_X_MAX + gid.x;
    if (gid.x >= tiles.x || gid.y >= tiles.y)
    {
        if (gi == 0u)
        {
            Tiles[tile * FE_TILE_STRIDE] = 0u; Tiles[tile * FE_TILE_STRIDE + FE_TILE_RAW] = 0u;
            Tiles[tile * FE_TILE_STRIDE + FE_TILE_WANT] = 0u;
        }
        return;
    }
    float3 ro = feView(_CameraPos);
    float3 cr[4], dc = 0.0;
    [unroll] for (uint q = 0u; q < 4u; q++)
    {
        float2 px = (float2)(gid.xy * FE_TILE) + float2((q & 1u) ? (float)FE_TILE : 0.0, (q & 2u) ? (float)FE_TILE : 0.0);
        float2 uvc = px / res;
        float4 f = mul(_InvViewProjMatrix, float4(uvc.x * 2.0 - 1.0, 1.0 - uvc.y * 2.0, 1.0, 1.0));
        cr[q] = normalize(feView(f.xyz / f.w) - ro);
        dc += cr[q];
    }
    dc = normalize(dc);
    float cosA = min(min(dot(dc, cr[0]), dot(dc, cr[1])), min(dot(dc, cr[2]), dot(dc, cr[3])));
    cosA = max(cosA * 0.998, 0.05);
    float tanA = sqrt(1.0 - cosA * cosA) / cosA, secA = 1.0 / cosA;
    uint base = tile * FE_TILE_STRIDE;
    if (gi == 0u)
    {
        gNN = 0u; gNB = 0u; gNK = 0u;
        gNPrev = Tiles[base + FE_TILE_RAW] >> 16;
    }
    GroupMemoryBarrierWithGroupSync();
    // This frame's half of the per-source table takes this tile's last candidate count; last frame's half is read.
    uint tag = (uint)_Frame & 255u;
    uint writeHalf = ((uint)_Frame & 1u) * FE_SOURCE_SLOTS;
    uint readHalf = (((uint)_Frame & 1u) ^ 1u) * FE_SOURCE_SLOTS;
    uint ownCount = (tag << 24) | min(gNPrev, 16777215u);
    for (uint inst = gi; inst < FE_N_MAX; inst += 64u)
    {
        float4 pt = Frame[inst * FE_FRAME_STRIDE + 3u];
        if (pt.z > 0.5)
        {
            uint cells = feTypeCells((uint)(pt.w + 0.5));
            for (uint c = 0u; c < cells; c++)
            {
                uint k = inst * FE_CELLS_CAP + c;
                float4 s2 = Sources[k * 3u + 2u];
                bool lit = any(s2.rgb > 1e-5);
                if (lit || s2.w >= 0.5)   // a lit beam, or a wide source lit or dark (dark ones count, never draw)
                {
                    float4 s0 = Sources[k * 3u], s1 = Sources[k * 3u + 1u];
                    if (s2.w < 0.5)
                    {
                        // The beam, or its mirror image in the deck (the beam pass reflects beams in a glossy deck).
                        float reach = feBeamReach(s0.xyz, s1.xyz), seg = reach / 8.0;
                        bool hit = false;
                        for (uint sgm = 0u; sgm < 8u; sgm++)
                        {
                            float t = ((float)sgm + 0.5) * seg;
                            float3 c = s0.xyz + s1.xyz * t;
                            float r = s0.w + (t + 0.5 * seg) * s1.w + 0.5 * seg;
                            hit = hit || sphereInCone(c, r, ro, dc, tanA, secA)
                                      || (floor_gloss > 0.0 && sphereInCone(float3(c.x, -c.y, c.z), r + 0.3 * c.y, ro, dc, tanA, secA));
                        }
                        if (hit)
                        {
                            uint j;
                            InterlockedAdd(gNN, 1u, j);
                            if (j < FE_TILE_MAX_NARROW) gN[j] = k;
                        }
                    }
                    else if (sphereInCone(s0.xyz, FE_WASH_RANGE, ro, dc, tanA, secA))
                    {
                        // A tile that did not list the source last frame adds its own last count to the table's.
                        InterlockedAdd(gNB, 1u);
                        if (gNPrev > 0u) raiseTagged(FE_BROAD_CROWD + writeHalf + k, ownCount, tag);
                        float crowd = max((float)lastTagged(FE_BROAD_CROWD + readHalf + k, tag), (float)gNPrev);
                        float keep = crowd <= FE_BROAD_TARGET ? 1.0 : saturate(FE_BROAD_TARGET / crowd);
                        if (lit && (keep >= 1.0 || sourceRandom(k) < keep))
                        {
                            uint j;
                            InterlockedAdd(gNK, 1u, j);
                            uint q = clamp((uint)round(keep * 32767.0), 1u, 32767u);
                            if (j < FE_TILE_MAX_BROAD) gB[j] = k | (q << 17);
                        }
                    }
                }
            }
        }
    }
    GroupMemoryBarrierWithGroupSync();
    uint nn = min(gNN, FE_TILE_MAX_NARROW), nb = min(gNK, FE_TILE_MAX_BROAD);
    if (gi == 0u)
    {
        Tiles[base] = nn | (nb << 16);
        Tiles[base + FE_TILE_RAW] = min(gNN, 65535u) | (min(gNB, 65535u) << 16);
        Tiles[base + FE_TILE_WANT] = gNK;
    }
    for (uint a = gi; a < nn; a += 64u) Tiles[base + 1u + a] = gN[a];
    for (uint b = gi; b < nb; b += 64u) Tiles[base + 1u + FE_TILE_MAX_NARROW + b] = gB[b];
}
