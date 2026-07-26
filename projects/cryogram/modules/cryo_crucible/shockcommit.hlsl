// CRYOGRAM / SPECIMEN — commit shock state for the next cook.

struct Shock {
    float2 center;
    float birth;
    float strength;
    float seed;
    float active;
    float2 pad;
};

StructuredBuffer<Shock> Src : register(t0);
RWStructuredBuffer<Shock> Dst : register(u0);

[numthreads(9, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x > 8u) return;
    Dst[tid.x] = Src[tid.x];
}
