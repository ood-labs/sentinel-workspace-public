// Trace_Canvas: line art for Laser Trace, drawn in the 16:9 projection frame. Coordinates are frame
// units: x 0..16/9 across, y 0..1 down. One image feeds both the video projector and Laser Trace
// (Fit Stretch maps the frame to +-1 on both axes, the whole mapped 16:9 frame).
//
// What each element tests on a real laser:
//   star     sharp corners (corner dwell)            circle  a smooth closed loop (the seam)
//   wave     an open stroke with two ends (end dwell) dots    spots under Laser Trace's dot size,
//                                                              traced as dwells with Dots on
static const float FW = 16.0 / 9.0;
static const float PI = 3.14159265;

float segD(float2 p, float2 a, float2 b)
{
    float2 d = b - a;
    return length(p - a - d * saturate(dot(p - a, d) / max(dot(d, d), 1e-9)));
}

// Distance to the nearest line of the art, and to the nearest dot centre, in frame units.
void artDistance(float2 p, out float lineD, out float dotD)
{
    float t = _Time;
    lineD = 1e9; dotD = 1e9;

    // Star outline, rotating, left of centre.
    float2 sc = float2(FW * 0.27, 0.52);
    float sr = 0.24, si = sr * 0.42, sa = t * 0.35;
    float2 prev = sc + sr * float2(sin(sa), -cos(sa));
    [unroll] for (int k = 1; k <= 10; k++)
    {
        float a = sa + k * PI / 5;
        float r = (k & 1) ? si : sr;
        float2 q = sc + r * float2(sin(a), -cos(a));
        lineD = min(lineD, segD(p, prev, q));
        prev = q;
    }

    // Circle outline, breathing, right of centre.
    float2 cc = float2(FW * 0.72, 0.46);
    float cr = 0.17 + 0.03 * sin(t * 1.3);
    lineD = min(lineD, abs(length(p - cc) - cr));

    // An open wave along the bottom, travelling.
    float x0 = FW * 0.14, x1 = FW * 0.86;
    if (p.x > x0 - 0.01 && p.x < x1 + 0.01)
    {
        float x = clamp(p.x, x0, x1);
        float y = 0.86 + 0.045 * sin(x * 9 - t * 2.2);
        float dy = 0.045 * 9 * cos(x * 9 - t * 2.2);
        lineD = min(lineD, abs(p.y - y) / sqrt(1 + dy * dy) + max(max(x0 - p.x, p.x - x1), 0));
    }

    // Dots: a small constellation across the top that twinkles, about half lit at a time. Each dot
    // is its own stroke, so it pays a blank jump plus the scanner's blank guard on both sides
    // (roughly 3.5 ms at 20 kpps on the studio profile): a handful of dots, not a sky full.
    [unroll] for (int j = 0; j < 6; j++)
    {
        float2 h = frac(sin(float2(j * 12.9898 + 1.7, j * 78.233 + 4.1)) * 43758.5453);
        float2 c = float2(FW * (0.08 + 0.84 * (j + 0.2 + 0.6 * h.x) / 6), 0.07 + 0.16 * h.y);
        float on = step(0.5, frac(t * 0.4 + h.x * 3.1));
        if (on > 0.5) dotD = min(dotD, length(p - c));
    }
}

// Coverage at one pixel: `px` is the size of this pixel in frame units, per axis, so the square
// trace pass (stretched in x) still draws lines of the right width in frame units.
float3 artColour(float2 p, float2 px)
{
    float lineD, dotD;
    artDistance(p, lineD, dotD);
    float aa = max(px.x, px.y);
    float l = 1 - smoothstep(line_width * 0.5 - aa * 0.5, line_width * 0.5 + aa * 0.5, lineD);
    // A dot is a single-pixel beam: a hard point at least one pixel across in whichever pass is
    // drawing (never a soft disc, which Laser Trace would trace as a tiny circle).
    float d = dotD <= max(dot_radius, max(px.x, px.y) * 0.71) ? 1 : 0;
    return max(line_color * l, dot_color * d);
}
