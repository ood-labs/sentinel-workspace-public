// KA_Pose / pose_frame.hlsli — the scope's geometry: ONE function of the live extent, called by the
// drawing (scope.hlsl) and the type (layout.hlsl), so a bar, its row number and its frame cannot
// disagree at any output size.
//
//   title row
//   four channel stations, side by side          (layout only: kit panes with live phase wheels)
//   the joint matrix: one row per live arm by six columns, A1..A6, under a header strip
//   the tool-height strip, aligned to the matrix columns, the floor drawn on it
//   the keycap footer
#ifndef KA_POSE_FRAME_HLSLI
#define KA_POSE_FRAME_HLSLI

struct PoFrame
{
    float  s;          // ui scale (1 at the 1024 x 640 reference)
    float4 head;       // the title row
    float4 stations;   // the band the four channel panes share
    float4 mat;        // the matrix plate
    float4 rows;       // the matrix rows, under its header strip
    float  colX0;      // where the six joint columns start (the gutter is left of it)
    float  colW;       // one joint column
    float4 tool;       // the tool-height plate
    float4 plot;       // its plot: the floor is plot.w, the band under it shows a tool below the floor
    float4 foot;       // the keycap footer
};

PoFrame poFrame(float2 R)
{
    PoFrame F;
    float s = kaUiScale(R);
    F.s = s;
    float4 r = float4(16.0 * s, 0.0, R.x - 16.0 * s, R.y);
    F.head = ilCutTop(r, 34.0 * s);
    F.foot = ilCutBottom(r, 30.0 * s);
    F.stations = ilCutTop(r, 88.0 * s);
    r.y += 8.0 * s;
    F.tool = ilCutBottom(r, clamp((r.w - r.y) * 0.17, 64.0 * s, 120.0 * s));
    r.w -= 8.0 * s;
    F.mat = r;
    F.rows = float4(r.x, r.y + 24.0 * s, r.z, r.w - 4.0 * s);
    F.colX0 = r.x + 68.0 * s;
    F.colW = max(r.z - 8.0 * s - F.colX0, 6.0) / 6.0;
    F.plot = float4(F.colX0, F.tool.y + 8.0 * s, F.tool.z - 8.0 * s, F.tool.w - 12.0 * s);
    return F;
}

float4 poStation(PoFrame F, uint c)
{
    float gap = 8.0 * F.s;
    float bw = (F.stations.z - F.stations.x - 3.0 * gap) * 0.25;
    float x = F.stations.x + (float)c * (bw + gap);
    return float4(x, F.stations.y, x + bw, F.stations.w);
}

// Rows grow to fill when the cell is small and compress to 4 px when it is full. A fixed small row
// wasted two thirds of the matrix at the counts people actually run.
float poRowH(PoFrame F, float liveN) { return clamp((F.rows.w - F.rows.y) / max(liveN, 1.0), 4.0, 26.0 * F.s); }

// The x of the tool stem for live ordinal `ord` of n.
float poStemX(PoFrame F, uint ord, float n)
{
    return lerp(F.plot.x + 10.0 * F.s, F.plot.z - 10.0 * F.s, (n > 1.0) ? ((float)ord / (n - 1.0)) : 0.5);
}

// Pixels per metre on the tool strip, sized to the tallest tool so far.
float poToolPpm(PoFrame F, float maxTool) { return (F.plot.w - F.plot.y) / max(max(maxTool, 1.0) * 1.10, 0.5); }

#endif
