// CRYOGRAM / CONSOLE — commit probe state for the next cook.

struct Probe {
    float2 pos;
    float radius;
    float strength;
    float kind;
    float age;
    float id;
    float active;
};

StructuredBuffer<Probe> Src : register(t0);
RWStructuredBuffer<Probe> Dst : register(u0);

[numthreads(33, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x > 32u) return;
    Dst[tid.x] = Src[tid.x];
}
