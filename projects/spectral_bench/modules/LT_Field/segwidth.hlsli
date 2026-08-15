// LT_Field / segwidth.hlsli — HOW WIDE IS THIS RAY, HERE?
//
// Include AFTER declaring `StructuredBuffer<PathSeg> Paths`. Both the binner and the renderer
// call this, and they must get the same answer: the binner decides which tiles a segment lands
// in, the renderer decides how far from the segment it will still put ink, and any disagreement
// draws a staircase along the beam at the tile size.
//
// A fixed width is wrong everywhere except at the source. Refraction into glass at a steep
// incidence spreads a bundle by 1/cos, a lens squeezes it, the internal-reflection branch leaves
// the exit face strongly divergent. So ask the NEIGHBOURING RAY where it is at the same
// interaction and draw this one just wide enough to meet it. One extra buffer read, and the beam
// then narrows through a focus and fans through a prism entirely on its own.
//
// Doing this per segment rather than taking the worst case globally is not an optimisation, it is
// the difference between working and not: a uniform worst-case reach put every segment into a
// hundred tiles at once and overflowed the bin lists across half the frame.
#ifndef LT_SEGWIDTH_HLSLI
#define LT_SEGWIDTH_HLSLI

#include "../_shared/optics.hlsli"
#include "view.hlsli"

float ltSegWidth(PathSeg g, float coreW, float ppb,
                 uint nRay, uint nWave, uint nBranch, uint stride)
{
    if (nRay <= 1u) return coreW;

    uint lane = (uint)g.lane;
    uint bIdx = lane % nBranch;
    uint wIdx = (lane / nBranch) % nWave;
    uint rIdx = lane / (nBranch * nWave);
    uint rN = (rIdx + 1u < nRay) ? (rIdx + 1u) : (rIdx - 1u);

    uint slotN = ((rN * nWave + wIdx) * nBranch + bIdx) * stride + (uint)g.depth;
    if (slotN >= (uint)LT_PATH_TOTAL) return coreW;

    PathSeg gn = Paths[slotN];
    // Only trust the neighbour if it is alive AND still in the same medium: a ray that took a
    // different route at the last interface is not a neighbour any more, it is a different beam.
    if (gn.power <= 1e-4 || abs(gn.ior - g.ior) >= 1e-3) return coreW;

    float2 dir = g.b - g.a;
    float ln = length(dir);
    if (ln <= 1e-6) return coreW;

    float2 nrm = ltPerp(dir / ln);
    float sp = abs(dot((gn.a + gn.b) * 0.5 - (g.a + g.b) * 0.5, nrm)) * ppb;
    return clamp(max(coreW, sp * 0.5), coreW, coreW * LT_WIDTH_MAX);
}

// The radius this segment actually puts ink out to. Both passes use it.
//
// The core is a flat-top ribbon with a HARD edge, so it reaches exactly its half-width plus the
// antialiasing margin — no 3-sigma tail. Only the atmospheric halo, which is still a gaussian,
// needs the wide bound. Switching the core from a gaussian to a ribbon therefore SHRANK the
// binning footprint even as the width cap tripled.
float ltSegReach(float localW, float coreW, float haze)
{
    float sw = max(coreW * 2.5, 1.8);
    return max(max(localW + 2.0, sw * 6.0), ltHaloW(coreW, haze) * 3.0 + 4.0);
}

#endif
