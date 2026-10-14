// Temporal anti-aliasing, the raster side. Every raster pass draws with this frame's sub-pixel offset from a Halton
// (2, 3) sequence over 8 frames, so a pixel samples a different part of a thin batten or truss tube each frame;
// taa.hlsl averages the frames along the camera. With taa off nothing jitters.
#ifndef SS_TAA_HLSLI
#define SS_TAA_HLSLI
float taaHalton(uint i, uint b)
{
    float f = 1.0, r = 0.0;
    [loop] while (i > 0u) { f /= (float)b; r += f * (float)(i % b); i /= b; }
    return r;
}
// This frame's offset in pixels, -0.5..0.5.
float2 taaJitter()
{
    uint i = ((uint)_Frame) % 8u + 1u;
    return float2(taaHalton(i, 2u), taaHalton(i, 3u)) - 0.5;
}
// The clip-space position of a world point, jittered.
float4 taaClip(float3 world)
{
    float4 c = mul(_ViewProjMatrix, float4(world, 1.0));
    if (taa > 0.5) c.xy += taaJitter() * 2.0 / _Resolution.xy * c.w;
    return c;
}
#endif
