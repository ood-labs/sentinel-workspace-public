// The plot contract between the Path Desk (writer) and the Plotter (reader): the published "Path"
// buffer, the plotter's four pens and its home.
//
// "Path" - float4 records, positions in program pixels of a 1280 x 720 frame (y down):
//   0           (paths, pen-down length px, samples in use, anchors in use)
//   1..6        path p: (first sample, sample count, length px, closed + 2 * pen)
//   7..126      anchor j of path p at 7 + 20p + j: (s px along the path, turn rad, x px, y px);
//               turn is how far the tangent breaks at the anchor (0 where it is smooth)
//   127..1150   samples spaced evenly along each path's length, both ends included (a closed path
//               repeats its start): (x px, y px, heading rad, curvature 1/px, + turning clockwise
//               on screen). A path with fewer than two anchors has no samples.
// Paths plot in index order; a consumer walks 0 .. paths-1 and skips any with no samples.
#ifndef PLOT_HLSLI
#define PLOT_HLSLI

#define PLOT_PATHS    6u
#define PLOT_AMAX     20u
#define PLOT_HEAD     0u
#define PLOT_PATH0    1u
#define PLOT_ANCHOR0  7u
#define PLOT_SAMPLE0  127u
#define PLOT_SAMPLES  1024u
#define PLOT_RECORDS  1151u
#define PLOT_W        1280.0
#define PLOT_H        720.0
#define PLOT_HOME     float2(36.0, 36.0)     // where the pen parks between plots

// The pens: the colour of a full line on white paper, display sRGB.
float3 plotInk(uint pen)
{
    pen &= 3u;
    return pen == 0u ? float3(0.118, 0.165, 0.267)      // blue-black
         : pen == 1u ? float3(0.435, 0.302, 0.188)      // sepia
         : pen == 2u ? float3(0.796, 0.278, 0.165)      // vermilion
         :             float3(0.255, 0.365, 0.310);     // verdigris
}

uint  plotPen(float4 pathRec)    { return (uint)(pathRec.w * 0.5); }
bool  plotClosed(float4 pathRec) { return frac(pathRec.w * 0.5) > 0.25; }

#endif
