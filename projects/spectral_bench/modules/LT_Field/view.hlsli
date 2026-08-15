// LT_Field / view.hlsli — the ONE mapping between bench space and the program image, plus the
// tile grid the binner and the renderer must agree about exactly.
//
// If the binner expanded a segment's bounds in one space and the renderer measured distance in
// another, beams would vanish along tile seams — which reads as a physics bug and is a transform
// bug. Both passes call these.
#ifndef LT_FIELD_VIEW_HLSLI
#define LT_FIELD_VIEW_HLSLI

#include "../_shared/bench.hlsli"

// The program image is a fixed 1280x720, and bench space is 1 x 0.5625, so at zoom 1 one bench
// unit is exactly the frame width and the bench maps corner to corner with no letterbox.
#define FIELD_W 1920
#define FIELD_H 1080

// 32-pixel tiles, not 16. A segment's footprint spills a fixed number of PIXELS past its line,
// so halving the tile size quadruples how many tiles each segment has to be inserted into — and
// the lists near the prism, where every lane in the graph converges, are what overflow first.
#define LT_TILE     32
#define LT_TILES_X  ((FIELD_W + LT_TILE - 1) / LT_TILE)   // 60
#define LT_TILES_Y  ((FIELD_H + LT_TILE - 1) / LT_TILE)   // 34
#define LT_TILES    (LT_TILES_X * LT_TILES_Y)             // 2040

// [0] = count, [1] = overflow flag, [2 .. 4095] = segment indices.
//
// Sized by the WORST tile, measured with the Occupancy view rather than guessed. That tile is not
// the one containing the prism — it is anywhere along an UN-DISPERSED run, where every wavelength
// is still collinear and a single tile therefore holds one segment per lane. Tile size cannot help
// with that: exactly-overlapping segments land in the same tile however the grid is cut. So the
// capacity has to cover the full lane count, 40 x 32 x 3.
#define LT_BIN_STRIDE 4096
#define LT_BIN_CAP    (LT_BIN_STRIDE - 2)

float  ltPxPerBench(float zoom) { return (float)FIELD_W * max(zoom, 1e-3); }
float2 ltFieldToPix(float2 b, float2 centre, float zoom, float2 res)
{
    return (b - centre) * ltPxPerBench(zoom) + res * 0.5;
}
float2 ltPixToField(float2 p, float2 centre, float zoom, float2 res)
{
    return centre + (p - res * 0.5) / ltPxPerBench(zoom);
}

// BEAM FOOTPRINT. The binner expands a segment's bounds by this and the renderer culls at this,
// and they MUST be the same number: bin tighter than you draw and beams get chopped at tile
// seams, which reads as dashed light and looks like a physics fault.
// A ray's HALF-WIDTH: half the gap to its neighbour, so the ribbons the renderer draws tile edge
// to edge and reconstruct the beam SHEET rather than summing N overlapping filaments. `widthMM` is
// a floor, which is what lets a single-ray source still draw something.
//
// A single ray owns the whole aperture; N rays each own a slice of it.
float ltCoreW(float ppb, float widthMM, float apertureBench, uint raysPer)
{
    float spacing = (raysPer > 1u) ? (apertureBench * ppb / (float)(raysPer - 1u))
                                   : (apertureBench * ppb);
    return max(max(ltFromMM(max(widthMM, 0.02)) * ppb * 0.5, spacing * 0.5), 0.05);
}
// How far the per-segment width is allowed to grow above the base. The renderer widens each ray
// to meet its neighbour (see scene.hlsl), and the binner has to expand by the SAME worst case or
// the widened part of a beam gets clipped at tile boundaries — which draws a 16-pixel staircase
// along every beam and reads as a rendering fault rather than as a binning one.
// The internal-reflection branch leaves the exit face strongly divergent, so its rays are far
// apart within a few centimetres. A flat-top ribbon has a HARD edge rather than a 3-sigma tail, so
// its reach grows linearly with width instead of triply — which is what makes a cap this generous
// affordable at all.
#define LT_WIDTH_MAX 24.0

// The scatter halo is atmospheric and stays at the base width: it is a property of the air, not
// of how far apart this particular pair of rays happens to be. Keeping it fixed is also what
// keeps the reach — and therefore the number of tiles each segment lands in — bounded.
float ltHaloW(float coreW, float haze) { return max(coreW, 0.9) * (3.0 + haze * 7.0); }


#endif
