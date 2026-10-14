// Plotter - the machine's record layout and the shared helpers.
//
// "plan" buffer (float4 records; 0..3 persist - they are the machine):
//   0      (state, path, s px along it, timer s)
//   1      (x, y, pen-down distance along the plot px, pen down 0 | 1)       <- control outputs
//   2      (speed px/s, plots finished, last mark's heading rad, ink blot pending 0 | 1)
//   3      (travel from x, from y, to x, to y)
//   4      (travel duration s, -, -, -)
//   5      (marks this cook, -, -, -)
//   6      the marks' bounds (x0, y0, x1, y1), padded by the widest nib
//   7..134     64 marks, two records each: (a.x, a.y, b.x, b.y), (density, pen, half width, caps)
//              caps: bit 0 round start (a stroke begins or turns sharply), bit 1 round end
//   135..1158  the speed limit at each sample of the Path (px/s), planned every cook
#ifndef PLOTTER_HLSLI
#define PLOTTER_HLSLI

#include "../_shared/plot.hlsli"

#define PL_STATE   0u
#define PL_PEN     1u
#define PL_MOTION  2u
#define PL_TRAVEL  3u
#define PL_TRAVEL2 4u
#define PL_NMARKS  5u
#define PL_BOUNDS  6u
#define PL_MARK0   7u
#define PL_MARKS   64u
#define PL_PROF0   (PL_MARK0 + 2u * PL_MARKS)      // 135
#define PL_COUNT   (PL_PROF0 + PLOT_SAMPLES)       // 1159

// the pencil guide: 1280 x 720 entries (cook << 8 | coverage), then the pencil pass's cook number
#define PL_PENCIL_COOK (1280u * 720u)

// the machine's states
#define ST_HOME    0u      // parked between plots
#define ST_TRAVEL  1u      // pen up, moving to the next path (or home)
#define ST_DROP    2u      // lowering the pen onto the paper
#define ST_DRAW    3u      // pen down, following the path
#define ST_LIFT    4u      // raising the pen

#define CAP_START  1u
#define CAP_END    2u

// NaN or infinity, by bit pattern (FXC folds isnan() away without /Gis)
bool badValue(float4 v) { return any((asuint(v) & 0x7F800000u) == 0x7F800000u); }

float3 srgbToLinear(float3 c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
float3 linearToSrgb(float3 c) { c = saturate(c); return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055; }

#endif
