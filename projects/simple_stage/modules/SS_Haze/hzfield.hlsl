// SS_Haze / hzfield — the Haze Field the renderer lights (layout: ss_haze.hlsli). This frame's haze (the slot
// hzdcorr just wrote), the air after this frame's projection, cell-centred, and the wisp noise with its wrapped
// border texels, so hardware bilinear is seamless across every tile's wrap.
#include "hz_grid.hlsli"
StructuredBuffer<float4> T : register(t0);
StructuredBuffer<float> D : register(t1);
StructuredBuffer<float4> A : register(t2);
StructuredBuffer<float> N : register(t3);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (id.x >= W || id.y >= H) return;
    float4 o = 0;
    int3 c;
    if (id.y < HF_AIR_Y)
    {
        if (atlasCell(id.xy - uint2(0, HF_DEN_Y), FX, FY, FZ, W, c))
        {
            uint cur = (1u - ((uint)T[0].x & 1u)) * FN;
            o = float4(D[cur + fIdx(c)], 0.0, 0.0, 1.0);
        }
    }
    else if (id.y < HF_NOI_Y)
    {
        if (atlasCell(id.xy - uint2(0, HF_AIR_Y), AX, AY, AZ, W, c))
        {
            float4 a = A[RA_U + aIdx(c)];
            float ux = c.x + 1 < AX ? A[RA_U + aIdx(c + int3(1, 0, 0))].x : 0.0;
            float vy = c.y + 1 < AY ? A[RA_U + aIdx(c + int3(0, 1, 0))].y : 0.0;
            float wz = c.z + 1 < AZ ? A[RA_U + aIdx(c + int3(0, 0, 1))].z : 0.0;
            o = float4(0.5 * float3(a.x + ux, a.y + vy, a.z + wz), a.w);
        }
    }
    else if (id.y < HF_HDR_Y)
    {
        uint2 q = id.xy - uint2(0, HF_NOI_Y);
        uint across = W / HZN_P;
        uint tx = q.x / HZN_P, z = (q.y / HZN_P) * across + tx;
        if (tx < across && z < 64u)
        {
            // texel j of a tile holds lattice coordinate (j - 1) mod 64
            uint jx = (q.x % HZN_P + 63u) & 63u, jy = (q.y % HZN_P + 63u) & 63u;
            o = N[jx + 64u * jy + 4096u * z].xxxx;
        }
    }
    else if (id.x == 0u)
        o = float4(T[1].w, 1.0, haze_base, 0.0);
    OutputUAV[id.xy] = fin4(o);
}
// rev 3 (headers changed: the shader cache keys on this file)
