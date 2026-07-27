// 2E1 Step 0 / part 2 — 2D (tau, theta) dispatch.
//
// The comb filter matrix is naturally two-dimensional: one axis of candidate
// beat periods, one of candidate phases. This proves the grid dispatches and
// guards correctly at the real 100 x 160 shape before any filtering logic
// depends on it.
//
// Each record also stores its own 1D-flattened index. That is the reserve
// fallback the phase doc keeps in hand, and writing it here means a switch to a
// flattened dispatch would be a change of dispatch shape only, against an
// index mapping this run has already verified.

struct R4 { float a, b, c, d; };

RWStructuredBuffer<R4> Comb : register(u0);

static const uint NTAU   = 100u;   // candidate periods
static const uint NTHETA = 160u;   // candidate phases

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint tau = tid.x, th = tid.y;
    // The allocation is rectangular and the dispatch rounds UP to whole groups
    // (13 x 20 x 8 x 8 = 104 x 160), so four columns of threads per row are out
    // of domain. Guarding rather than sizing exactly is deliberate: a real comb
    // range will not be a multiple of the group size either.
    if (tau >= NTAU || th >= NTHETA) return;

    uint flat = tau * NTHETA + th;
    R4 v;
    v.a = (float)tau;
    v.b = (float)th;
    v.c = (float)flat;
    v.d = _Time;
    Comb[flat] = v;
}
