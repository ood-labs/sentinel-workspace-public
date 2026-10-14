// SS_Haze / hzmg — the pressure solve: a geometric multigrid V-cycle (EmberGen's projection: multigrid
// cycle, coarse solve, then smoothing that enforces the solid boundaries).
//
// Per cell: L p = sum over open neighbours (p_n - p_c) = f, f = the divergence of the face velocities
// (hzdiv). Solids and the hall's boundary drop out of the sum (no flow through them). Projecting with
// u_face -= p_c - p_(c-e) then leaves every cell divergence free.
//
// Levels: 0 = 88 x 40 x 120 (the air grid), 1 = 44 x 20 x 60, 2 = 22 x 10 x 30, 3 = 11 x 5 x 15.
// Smooth (red-black Gauss-Seidel, a little over-relaxed) -> restrict the residual (f_coarse = 4 x mean of
// the 8 children: the stencil carries h^2) -> ... -> level 3 solved in one thread group -> prolong each
// correction trilinearly, smooth. Level 0 starts from last frame's pressure (warm start). Every pass works
// in place on its own level's cells only: red reads black and writes red, restriction reads the finer
// level and writes the coarser, prolongation the reverse.
//
// Wrappers set MG_OP (1 smooth, 2 restrict, 3 coarse solve, 4 prolong), MG_LEVEL and MG_COLOR.
#include "hz_grid.hlsli"
#ifndef MG_OMEGA
#define MG_OMEGA 1.15
#endif
RWStructuredBuffer<float4> A : register(u0);

int3 mgDim(uint l) { return int3(AX >> l, AY >> l, AZ >> l); }
uint mgCount(uint l) { int3 d = mgDim(l); return (uint)(d.x * d.y * d.z); }
uint mgIdx(uint l, int3 c) { int3 d = mgDim(l); return RA_MG + MG_OFF[l] + ((uint)c.z * d.y + (uint)c.y) * d.x + (uint)c.x; }
int3 mgCoord(uint l, uint i) { int3 d = mgDim(l); return int3(i % d.x, (i / d.x) % d.y, i / (d.x * d.y)); }
bool mgOpen(uint l, int3 c)
{
    int3 d = mgDim(l);
    if (any(c < 0) || any(c >= d)) return false;
    return A[mgIdx(l, c)].z < 0.5;
}
float mgP(uint l, int3 c) { return A[mgIdx(l, c)].x; }

// A closed hall fixes pressure only up to a constant, and a warm-started solve lets it drift until
// p_c - p_n is lost to float precision. A tiny regularisation (L - eps) p = f pins it.
#define MG_EPS 1e-4
float mgEps(uint l) { return MG_EPS * (float)(1u << (2u * l)); }

static const int3 NB[6] = { int3(1, 0, 0), int3(-1, 0, 0), int3(0, 1, 0), int3(0, -1, 0), int3(0, 0, 1), int3(0, 0, -1) };

float nbSum(uint l, int3 c, out float n)
{
    float s = 0.0; n = 0.0;
    [unroll] for (uint k = 0; k < 6u; k++)
    {
        int3 q = c + NB[k];
        if (mgOpen(l, q)) { s += mgP(l, q); n += 1.0; }
    }
    return s;
}
float residual(uint l, int3 c)
{
    float4 m = A[mgIdx(l, c)];
    if (m.z > 0.5) return 0.0;
    float n;
    float s = nbSum(l, c, n);
    return m.y - (s - (n + mgEps(l)) * m.x);
}

#if MG_OP == 3
// level 3 (825 cells) in shared memory, one group of 256 threads, 96 over-relaxed red-black sweeps
#define C3 825u
groupshared float gp[C3];
groupshared float gf[C3];
groupshared float gs3[C3];
[numthreads(256, 1, 1)]
void main(uint3 gt : SV_GroupThreadID)
{
    uint t = gt.x;
    for (uint k = t; k < C3; k += 256u)
    {
        float4 m = A[RA_MG + MG_OFF[3] + k];
        gp[k] = 0.0; gf[k] = m.y; gs3[k] = m.z;
    }
    GroupMemoryBarrierWithGroupSync();
    int3 d = mgDim(3);
    [loop] for (uint it = 0; it < 96u; it++)
    {
        [unroll] for (uint col = 0; col < 2u; col++)
        {
            // single-exit body: no stores ahead of a `continue` (FXC can drop them)
            for (uint k = t; k < C3; k += 256u)
            {
                int3 c = mgCoord(3, k);
                if ((uint)((c.x + c.y + c.z) & 1) == col)
                {
                    float s = 0.0, n = 0.0;
                    [unroll] for (uint q6 = 0; q6 < 6u; q6++)
                    {
                        int3 q = c + NB[q6];
                        uint qi = ((uint)q.z * d.y + (uint)q.y) * d.x + (uint)q.x;
                        if (all(q >= 0) && all(q < d) && gs3[qi] < 0.5) { s += gp[qi]; n += 1.0; }
                    }
                    float g = (s - gf[k]) / (n + mgEps(3));
                    if (gs3[k] > 0.5) gp[k] = 0.0;
                    else if (n > 0.5) gp[k] = fin(lerp(gp[k], g, 1.7));
                }
            }
            GroupMemoryBarrierWithGroupSync();
        }
    }
    for (uint k2 = t; k2 < C3; k2 += 256u) A[RA_MG + MG_OFF[3] + k2] = float4(gp[k2], gf[k2], gs3[k2], 0.0);
}
#else
[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint l = MG_LEVEL;
    uint j = id.x;
    if (j >= mgCount(l)) return;
    int3 c = mgCoord(l, j);
    uint ai = RA_MG + MG_OFF[l] + j;
#if MG_OP == 1
    // red-black Gauss-Seidel, over-relaxed a little (EmberGen: "slightly bigger than 100%")
    if ((uint)((c.x + c.y + c.z) & 1) != MG_COLOR) return;
    float4 m = A[ai];
    if (m.z > 0.5) m.x = 0.0;
    else
    {
        float n;
        float s = nbSum(l, c, n);
        if (n > 0.5) m.x = fin(lerp(m.x, (s - m.y) / (n + mgEps(l)), MG_OMEGA));
    }
    A[ai] = m;
#elif MG_OP == 2
    // a cell of level l: gather the residual of its 8 children on level l - 1
    float4 m = A[ai];
    float r = 0.0;
    [unroll] for (uint k = 0; k < 8u; k++) r += residual(l - 1u, c * 2 + int3(k & 1u, (k >> 1) & 1u, k >> 2));
    m.x = 0.0;
    m.y = fin(4.0 * r / 8.0);
    A[ai] = m;
#elif MG_OP == 4
    // add the coarse correction (level l + 1), trilinear between coarse cell centres
    float4 m = A[ai];
    if (m.z < 0.5)
    {
        int3 dc = mgDim(l + 1u);
        float3 g = clamp(((float3)c + 0.5) * 0.5 - 0.5, 0.0, (float3)(dc - 1));
        int3 c0 = max(min((int3)floor(g), dc - 2), 0);
        float3 f = saturate(g - (float3)c0);
        float e[8];
        [unroll] for (uint k = 0; k < 8u; k++) e[k] = mgP(l + 1u, min(c0 + int3(k & 1u, (k >> 1) & 1u, k >> 2), dc - 1));
        float corr = lerp(lerp(lerp(e[0], e[1], f.x), lerp(e[2], e[3], f.x), f.y), lerp(lerp(e[4], e[5], f.x), lerp(e[6], e[7], f.x), f.y), f.z);
        m.x = fin(m.x + fin(corr));
    }
    A[ai] = m;
#endif
}
#endif
