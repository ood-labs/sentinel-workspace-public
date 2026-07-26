// CRYOGRAM / RELIEF — commit pulse state for the next cook.

struct Pulse {
    float2 center;
    float birth;
    float strength;
    float seed;
    float active;
    float2 pad;
};

StructuredBuffer<Pulse> Src : register(t0);
RWStructuredBuffer<Pulse> Dst : register(u0);

[numthreads(17, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x > 16u) return;
    Dst[tid.x] = Src[tid.x];
}
