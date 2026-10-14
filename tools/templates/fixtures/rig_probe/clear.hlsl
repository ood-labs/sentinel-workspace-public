// Clears the canvas: two keys per pixel, [2p] the nearest body (depth, shade) and [2p + 1] the brightest beam.
RWStructuredBuffer<uint> Canvas : register(u0);

#define RP_CANVAS_W 1280u   // as probe.hlsli
#define RP_CANVAS_H 720u

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x < RP_CANVAS_W * RP_CANVAS_H * 2u) Canvas[id.x] = 0u;
}
