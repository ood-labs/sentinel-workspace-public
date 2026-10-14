// BR_Render / hdrout.hlsl -- the "HDR" output for BR_Lens: linear scene radiance (no exposure,
// no tonemap) with, in alpha, the distance along the eye ray that each pixel's image moves with:
// the surface, or a sheer in front of a window, the trees outside, a mirror's virtual image.
// BR_Lens reprojects its glow through it. Do not judge this output by eye -- a capture
// composites RGB against that alpha (see the Preview output).
//
// Texels (0..19, 0) are NOT colour: they carry the camera this image was rendered with
// (br_camtexels.hlsli), passed straight through from the history, so BR_Lens reprojects between
// the cameras of the very images it holds -- whatever latency the links between the nodes have.
#include "render_common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    OutputUAV[tid.xy] = _Tex1.Load(int3(tid.xy, 0));
}
