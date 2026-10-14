// Plotter / plan - one thread: the speed limit along every path, then the machine's move for this
// cook, and the marks its pen laid on the way.
//
// Speed is planned the way plotter and CNC firmware plan it. Each sample's limit is the slower of
// the top speed and what a turn that tight allows (sqrt(cornering / curvature)); the pen is at rest
// at both ends of every path; then a forward and a backward pass cap how fast the speed may change
// (sqrt(v^2 + 2 * acceleration * spacing)). Curvature is read from the samples' headings - the
// heading change across a sample over the distance it spans - so a corner, where the heading jumps,
// reads as a very tight turn and the pen all but stops there.
//
// The machine: parked at home -> travel (pen up, minimum-jerk move) -> drop -> draw the path ->
// lift -> travel to the next path ... -> travel home, pause, start the next plot.
#include "plotter.hlsli"

StructuredBuffer<float4> W : register(t0);        // the Path Desk's "Path" (data input)
RWStructuredBuffer<float4> PL : register(u0);

static float g_vmax, g_alat, g_acc;

float wrapAngle(float a) { return a - 6.2831853 * floor((a + 3.14159265) / 6.2831853); }
bool  hasPath(uint p) { return p < PLOT_PATHS && W[PLOT_PATH0 + p].y >= 2.0; }

void planPath(uint p)
{
    float4 r = W[PLOT_PATH0 + p];
    uint first = (uint)r.x, n = (uint)r.y;
    float ds = r.z / (float)(n - 1u);
    bool closed = plotClosed(r);
    // what each turn allows (a closed path's last sample repeats its first)
    [loop] for (uint k = 0u; k < n; k++)
    {
        bool hasPrev = k > 0u || closed, hasNext = k + 1u < n || closed;
        uint kp = k > 0u ? k - 1u : (closed ? n - 2u : 0u);
        uint kn = k + 1u < n ? k + 1u : (closed ? 1u : n - 1u);
        float span = ((hasPrev ? 1.0 : 0.0) + (hasNext ? 1.0 : 0.0)) * ds;
        float turn = abs(wrapAngle(W[PLOT_SAMPLE0 + first + kn].z - W[PLOT_SAMPLE0 + first + kp].z));
        float kappa = turn / max(span, 1e-3);
        PL[PL_PROF0 + first + k] = float4(min(g_vmax, sqrt(g_alat / max(kappa, 1e-6))), kappa, 0.0, 0.0);
    }
    // at rest at both ends, then acceleration both ways
    PL[PL_PROF0 + first] = float4(0.0, PL[PL_PROF0 + first].y, 0.0, 0.0);
    PL[PL_PROF0 + first + n - 1u] = float4(0.0, PL[PL_PROF0 + first + n - 1u].y, 0.0, 0.0);
    [loop] for (uint f = 1u; f < n; f++)
    {
        float4 v = PL[PL_PROF0 + first + f];
        v.x = min(v.x, sqrt(PL[PL_PROF0 + first + f - 1u].x * PL[PL_PROF0 + first + f - 1u].x + 2.0 * g_acc * ds));
        PL[PL_PROF0 + first + f] = v;
    }
    [loop] for (int b = (int)n - 2; b >= 0; b--)
    {
        float4 v = PL[PL_PROF0 + first + (uint)b];
        float vn = PL[PL_PROF0 + first + (uint)b + 1u].x;
        v.x = min(v.x, sqrt(vn * vn + 2.0 * g_acc * ds));
        PL[PL_PROF0 + first + (uint)b] = v;
    }
}

// where path p is at distance s along it, and its planned speed there
float2 posAt(uint p, float s)
{
    float4 r = W[PLOT_PATH0 + p];
    uint first = (uint)r.x, n = (uint)r.y;
    float u = clamp(s / max(r.z, 1e-3), 0.0, 1.0) * (float)(n - 1u);
    uint k = min((uint)u, n - 2u);
    return lerp(W[PLOT_SAMPLE0 + first + k].xy, W[PLOT_SAMPLE0 + first + k + 1u].xy, u - (float)k);
}
float speedAt(uint p, float s)
{
    float4 r = W[PLOT_PATH0 + p];
    uint first = (uint)r.x, n = (uint)r.y;
    float u = clamp(s / max(r.z, 1e-3), 0.0, 1.0) * (float)(n - 1u);
    uint k = min((uint)u, n - 2u);
    return lerp(PL[PL_PROF0 + first + k].x, PL[PL_PROF0 + first + k + 1u].x, u - (float)k);
}

// the pen-down length of every path before p
float lengthBefore(uint p)
{
    float acc = 0.0;
    [loop] for (uint q = 0u; q < p && q < PLOT_PATHS; q++) if (hasPath(q)) acc += W[PLOT_PATH0 + q].z;
    return acc;
}

uint nextPath(uint after)        // the first path with samples after index `after` (PLOT_PATHS: none)
{
    [loop] for (uint q = after; q < PLOT_PATHS; q++) if (hasPath(q)) return q;
    return PLOT_PATHS;
}

// minimum-jerk: smooth start and stop, peak speed 1.875 x the average
float minJerk(float t) { t = saturate(t); return t * t * t * (10.0 + t * (-15.0 + 6.0 * t)); }
float minJerkRate(float t) { t = saturate(t); return 30.0 * t * t * (1.0 - t) * (1.0 - t); }
float travelTime(float dist) { return max(0.2, 1.875 * dist / max(travel, 50.0)); }

static uint g_marks;
static float4 g_bounds;

void mark(float2 a, float2 b, float density, uint pen, float halfW, uint caps)
{
    if (g_marks >= PL_MARKS) return;
    PL[PL_MARK0 + 2u * g_marks] = float4(a, b);
    PL[PL_MARK0 + 2u * g_marks + 1u] = float4(density, (float)pen, halfW, (float)caps);
    g_bounds = float4(min(g_bounds.xy, min(a, b) - halfW - 2.0), max(g_bounds.zw, max(a, b) + halfW + 2.0));
    g_marks++;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    g_vmax = clamp(speed, 50.0, 4000.0);
    g_alat = clamp(cornering, 50.0, 20000.0);
    g_acc = clamp(accel, 50.0, 20000.0);
    float liftT = clamp(lift, 0.02, 1.0);
    float dt = clamp(_DeltaTime, 0.0, 0.1);

    [loop] for (uint p = 0u; p < PLOT_PATHS; p++) if (hasPath(p)) planPath(p);

    float4 st = PL[PL_STATE], pen = PL[PL_PEN], mo = PL[PL_MOTION], tr = PL[PL_TRAVEL], tr2 = PL[PL_TRAVEL2];
    if (!(st.x >= 0.0 && st.x <= 4.0) || badValue(pen) || badValue(st))
    {
        st = float4(ST_HOME, 0.0, 0.0, 0.0);
        pen = float4(PLOT_HOME, 0.0, 0.0);
        mo = float4(0.0, 0.0, 0.0, 0.0);
    }
    if (all(pen.xy == 0.0)) pen.xy = PLOT_HOME;
    uint state = (uint)st.x, path = (uint)st.y;
    float s = st.z, timer = st.w;
    float spd = 0.0;
    g_marks = 0u;
    g_bounds = float4(1e9, 1e9, -1e9, -1e9);

    float t = dt;
    [loop] for (uint step = 0u; step < 12u && t > 0.0; step++)
    {
        if (state == ST_HOME)
        {
            timer += t;
            t = 0.0;
            uint q = nextPath(0u);
            if (timer >= 1.0 && q < PLOT_PATHS)
            {
                state = ST_TRAVEL;
                path = q;
                tr = float4(pen.xy, posAt(q, 0.0));
                tr2.x = travelTime(length(tr.zw - tr.xy));
                timer = 0.0;
            }
        }
        else if (state == ST_TRAVEL)
        {
            float use = min(t, max(tr2.x - timer, 0.0));
            timer += use;
            t -= use;
            float u = timer / max(tr2.x, 1e-3);
            pen.xy = lerp(tr.xy, tr.zw, minJerk(u));
            spd = length(tr.zw - tr.xy) * minJerkRate(u) / max(tr2.x, 1e-3);
            if (timer >= tr2.x)
            {
                pen.xy = tr.zw;
                timer = 0.0;
                if (path < PLOT_PATHS) state = ST_DROP;
                else
                {
                    state = ST_HOME;
                    mo.y += 1.0;             // a plot finished
                }
            }
        }
        else if (state == ST_DROP)
        {
            float use = min(t, max(liftT - timer, 0.0));
            timer += use;
            t -= use;
            if (timer >= liftT)
            {
                state = ST_DRAW;
                s = 0.0;
                timer = 0.0;
                mo.w = 1.0;                  // the nib rested on the paper: a small blot
            }
        }
        else if (state == ST_DRAW)
        {
            if (!hasPath(path))
            {
                state = ST_LIFT;
                timer = 0.0;
                continue;
            }
            float4 r = W[PLOT_PATH0 + path];
            uint penIx = plotPen(r);
            float len = r.z;
            float halfNib = 0.5 * clamp(nib, 0.5, 8.0);
            [loop] for (uint sub = 0u; sub < PL_MARKS && t > 0.0 && s < len; sub++)
            {
                if (g_marks >= PL_MARKS) { t = 0.0; break; }
                float v = max(speedAt(path, s), 8.0);         // never stalls on the rest points
                float stepLen = min(1.5, len - s);
                float stepT = stepLen / v;
                if (stepT > t) { stepLen = v * t; stepT = t; }
                float2 a = posAt(path, s);
                s += stepLen;
                t -= stepT;
                float2 b = posAt(path, s);
                spd = v;
                // ink: more where the pen is slow; a slower line is also a little wider
                float density = min(clamp(flow, 0.05, 4.0) * 360.0 / v, 6.0);
                float halfW = halfNib * (0.85 + 0.1 * min(density, 4.0));
                float2 dir = b - a;
                float heading = atan2(dir.y, dir.x);
                uint caps = 0u;
                if (mo.w > 0.5) { caps |= CAP_START; density += 1.2; mo.w = 0.0; }
                else if (abs(wrapAngle(heading - mo.z)) > 0.35) caps |= CAP_START;   // fill a sharp turn
                if (s >= len - 1e-3) caps |= CAP_END;
                mark(a, b, density, penIx, halfW, caps);
                mo.z = heading;
                pen.xy = b;
            }
            pen.z = lengthBefore(path) + s;
            if (s >= len - 1e-3)
            {
                state = ST_LIFT;
                timer = 0.0;
            }
        }
        else    // ST_LIFT
        {
            float use = min(t, max(liftT - timer, 0.0));
            timer += use;
            t -= use;
            if (timer >= liftT)
            {
                uint q = nextPath(path + 1u);
                tr.xy = pen.xy;
                if (q < PLOT_PATHS) { path = q; tr.zw = posAt(q, 0.0); }
                else { path = PLOT_PATHS; tr.zw = PLOT_HOME; }
                tr2.x = travelTime(length(tr.zw - tr.xy));
                state = ST_TRAVEL;
                timer = 0.0;
                pen.z = lengthBefore(min(path, PLOT_PATHS));
            }
        }
    }

    if (state == ST_HOME) pen.z = 0.0;
    pen.w = (state == ST_DRAW) ? 1.0 : 0.0;
    mo.x = spd;
    PL[PL_STATE] = float4((float)state, (float)path, s, timer);
    PL[PL_PEN] = pen;
    PL[PL_MOTION] = mo;
    PL[PL_TRAVEL] = tr;
    PL[PL_TRAVEL2] = tr2;
    PL[PL_NMARKS] = float4((float)g_marks, 0.0, 0.0, 0.0);
    PL[PL_BOUNDS] = g_bounds;
}
