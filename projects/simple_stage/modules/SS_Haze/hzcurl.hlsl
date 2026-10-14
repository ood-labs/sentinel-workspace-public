// SS_Haze / hzcurl — vorticity of the advected air at each cell centre, w = curl u (central differences
// of the cell-centred velocity), NEW -> CURL (xyz = w, w = |w|). hzforce turns it into vorticity
// confinement: the small eddies the grid's numerical diffusion smears away are fed back.
#include "hz_grid.hlsli"
StructuredBuffer<float4> T : register(t0);
RWStructuredBuffer<float4> A : register(u0);

float3 uc(int3 c)
{
    c = clamp(c, 0, int3(AX - 1, AY - 1, AZ - 1));
    float4 a = A[RA_NEW + aIdx(c)];
    float ux = c.x + 1 < AX ? A[RA_NEW + aIdx(c + int3(1, 0, 0))].x : 0.0;
    float vy = c.y + 1 < AY ? A[RA_NEW + aIdx(c + int3(0, 1, 0))].y : 0.0;
    float wz = c.z + 1 < AZ ? A[RA_NEW + aIdx(c + int3(0, 0, 1))].z : 0.0;
    return 0.5 * float3(a.x + ux, a.y + vy, a.z + wz);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= AN) return;
    float h = max(T[1].w, 0.05);
    int3 c = aCoord(i);
    float3 dx = uc(c + int3(1, 0, 0)) - uc(c - int3(1, 0, 0));
    float3 dy = uc(c + int3(0, 1, 0)) - uc(c - int3(0, 1, 0));
    float3 dz = uc(c + int3(0, 0, 1)) - uc(c - int3(0, 0, 1));
    float3 w = float3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x) / (2.0 * h);
    A[RA_CURL + i] = fin4(float4(w, length(w)));
}
// rev 3 (headers changed: the shader cache keys on this file)
