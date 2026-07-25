// CRYOGRAM / MEASUREMENT — commit this cook's tracks as next cook's history.
// Separate buffers rather than same-buffer ping-pong, matching the proven
// structured-buffer pattern used elsewhere in this workspace.

struct Track {
    float2 position;
    float2 velocity;
    float age;
    float confidence;
    float id;
    float active;
};

StructuredBuffer<Track> Src : register(t0);
RWStructuredBuffer<Track> Dst : register(u0);

[numthreads(97, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x > 96u) return;
    Dst[tid.x] = Src[tid.x];
}
