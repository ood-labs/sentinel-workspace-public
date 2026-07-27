// 2E1 — per-period reduction over phase.
//
// Collapses each row of the comb matrix to its best phase, so the tempo stage
// reads 100 elements instead of 16000. Without this the peak pick would be a
// 16000-element sweep on ONE thread every cook; here it is 160 reads on each of
// 100 threads, which is what the GPU is for.
//
// The winning phase is carried alongside the value. Re-deriving it later would
// mean a second full sweep of the matrix, and any drift between the two sweeps
// would put the reported beat phase on a different period than the reported
// tempo.

#include "common.hlsli"

StructuredBuffer<PS> C   : register(t0);   // (tau, theta) matrix
RWStructuredBuffer<PS> M : register(u0);   // per-tau maximum

static const uint NTAU   = 100u;
static const uint NTHETA = 160u;

[numthreads(8, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint ti = tid.x;
    if (ti >= NTAU) return;

    float best = -1.0, bestTh = 0.0, sum = 0.0;
    float bpm = 0.0, tau = 0.0;

    [loop] for (uint th = 0u; th < NTHETA; ++th) {
        PS c = C[ti * NTHETA + th];
        sum += c.a;
        if (c.a > best) { best = c.a; bestTh = (float)th; bpm = c.b; tau = c.c; }
    }

    PS o;
    o.a = max(best, 0.0);
    o.b = bpm;
    o.c = tau;
    o.d = bestTh / (float)NTHETA;          // winning phase, as a fraction of a beat
    // The row mean, kept so the tempo stage can form a peak-to-average ratio
    // without a second pass over the matrix.
    o.e = sum / (float)NTHETA;
    o.f = 0.0; o.g = 0.0; o.h = 0.0;
    M[ti] = o;
}
