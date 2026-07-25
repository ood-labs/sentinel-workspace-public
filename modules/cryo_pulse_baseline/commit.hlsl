// CRYOGRAM / PULSE — commit detector state for the next cook.

struct PS { float a, b, c, d, e, f, g, h; };

StructuredBuffer<PS> Src : register(t0);
RWStructuredBuffer<PS> Dst : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= 1167u) return;   // baseline: 654 state + header E + 512 hit slots
    Dst[tid.x] = Src[tid.x];
}
