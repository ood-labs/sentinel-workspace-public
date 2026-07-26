// 2E1 Step 0 / part 1 — partial-write persistence.
//
// Writes ONE ring slot per cook and nothing else. If persistent buffers keep
// untouched elements, slots n-1 and n-2 still carry their own older stamps; if
// the runtime clears or re-initialises the buffer, they read 0 and 2E1's onset
// history must be built on a banked commit copy instead.
//
// The cursor is read back out of the UAV's own header element rather than
// derived from _Time. A UAV is read-write, and one thread reading element 800
// while writing element n%800 has no race. Deriving it from _Time would make
// the stamps depend on cook rate and could skip or repeat a slot, which is
// exactly the confound the test is trying to exclude.

struct R4 { float a, b, c, d; };

RWStructuredBuffer<R4> Ring : register(u0);

static const uint NSLOTS = 800u;
static const uint HDR    = 800u;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x != 0u) return;

    R4 h = Ring[HDR];
    uint n = (uint)max(h.a, 0.0);
    uint slot = n % NSLOTS;

    R4 v;
    // 1-based, so a slot that was never written reads 0 and is distinguishable
    // from the slot legitimately written by cook 0.
    v.a = (float)(n + 1u);
    v.b = (float)slot;
    v.c = _Time;
    v.d = 0.0;
    Ring[slot] = v;

    h.a = (float)(n + 1u);
    h.b = (float)slot;
    h.c = _Time;
    h.d = 0.0;
    Ring[HDR] = h;
}
