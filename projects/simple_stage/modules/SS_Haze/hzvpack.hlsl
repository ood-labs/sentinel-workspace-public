// SS_Haze / hzvpack — the air as it stands at the start of the frame (last frame's projected flow), packed
// cell-centred into an atlas of z slices: rgb = velocity (m/s), a = temperature above ambient (K). Every
// back-trace this frame (the air's own advection and the haze's) reads it with hardware trilinear, and it is
// read the same frame through `pass:hzvpack`. 1024 x 440: 11 tiles of 88 x 40 across, 11 rows.
#include "hz_grid.hlsli"
StructuredBuffer<float4> A : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (id.x >= W || id.y >= H) return;
    int3 c;
    if (!atlasCell(id.xy, AX, AY, AZ, W, c)) { OutputUAV[id.xy] = 0; return; }
    float4 a = A[RA_U + aIdx(c)];
    float ux = c.x + 1 < AX ? A[RA_U + aIdx(c + int3(1, 0, 0))].x : 0.0;
    float vy = c.y + 1 < AY ? A[RA_U + aIdx(c + int3(0, 1, 0))].y : 0.0;
    float wz = c.z + 1 < AZ ? A[RA_U + aIdx(c + int3(0, 0, 1))].z : 0.0;
    OutputUAV[id.xy] = fin4(float4(0.5 * float3(a.x + ux, a.y + vy, a.z + wz), a.w));
}
// rev 3 (headers changed: the shader cache keys on this file)
