// Room light for the haze: the irradiance from every lit wash and strobe source at the centre of each cell of
// a coarse grid over the stage. The fog ray-march samples it trilinearly, so washes light the smoke as wide
// volumetric cones. Each group first stages the lit wide sources of the whole rig in groupshared memory.
#define GDTF_RENDER _Data2
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"

StructuredBuffer<float4> Sources : register(t0);
StructuredBuffer<float4> Frame : register(t1);
RWStructuredBuffer<float4> Grid : register(u0);

#include "../_shared/fe_fog.hlsli"

#define MAX_WIDE 640u      // 3 x 640 x 16 B of groupshared, under the 32 KB cs_5_0 limit
groupshared float4 gS0[MAX_WIDE], gS1[MAX_WIDE], gS2[MAX_WIDE];
groupshared uint gN;

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID, uint gi : SV_GroupIndex)
{
    if (gi == 0u) gN = 0u;
    GroupMemoryBarrierWithGroupSync();
    for (uint inst = gi; inst < FE_N_MAX; inst += 64u)
    {
        float4 pt = Frame[inst * FE_FRAME_STRIDE + 3u];
        if (pt.z > 0.5)
        {
            uint type = (uint)(pt.w + 0.5);
            uint me = feMaxEmitters();
            for (uint e = 0u; e < me; e++)
            {
                uint k = inst * FE_CELLS_CAP + FE_CELL_BASE_AT(type * me + e);
                float4 s2 = Sources[k * 3u + 2u];
                if (FE_EMITTER_AT(type * me + e).x != 0u && s2.w >= 0.2 && any(s2.rgb > 1e-5))
                {
                    uint j;
                    InterlockedAdd(gN, 1u, j);
                    if (j < MAX_WIDE) { gS0[j] = Sources[k * 3u]; gS1[j] = Sources[k * 3u + 1u]; gS2[j] = s2; }
                }
            }
        }
    }
    GroupMemoryBarrierWithGroupSync();
    uint cell = id.x;
    if (cell >= FE_GRID_X * FE_GRID_Y * FE_GRID_Z) return;
    uint3 c = uint3(cell % FE_GRID_X, (cell / FE_GRID_X) % FE_GRID_Y, cell / (FE_GRID_X * FE_GRID_Y));
    float3 x = FE_GRID_LO + ((float3)c + 0.5) / float3(FE_GRID_X, FE_GRID_Y, FE_GRID_Z) * (FE_GRID_HI - FE_GRID_LO);
    float3 E = 0.0;
    uint n = min(gN, MAX_WIDE);
    for (uint s = 0u; s < n; s++)
    {
        float3 v = x - gS0[s].xyz;
        float dd = max(dot(v, v), 0.36);
        E += gS2[s].rgb * feConeIntensity(gS1[s], gS2[s], v * rsqrt(dd)) / dd;
    }
    Grid[cell] = float4(E, 0.0);
}
