// Laser test shapes: curved, cornered, text and blank-heavy geometry for dialling in a scanner, authored
// in the same 16:9 frame as the Projection video (see xf). Scan Signal in ILDA scanner space (+y up).
//
// Drawn with the BLINK 2026 laser pen (blink26-motion _busk/busk_laser.hlsli, the laser-matched-
// content skill), in scan units instead of wall metres:
//   - The cycle is beam length: lit strokes run at Draw Speed, blank jumps cost a little.
//   - Few long strokes. Curves are emitted adaptively: each segment grows while its chord stays
//     within Curve Tolerance of the true curve, so a smooth arc is a handful of records, not
//     hundreds. Laser Out spends points per RECORD, so hundreds of tiny records crawl.
//   - A turn sharper than 60 degrees stops at the corner (a zero-length blank); gentle turns flow.
//   - finish() closes the cycle on its first point, caps an over-long cycle at Max Cycle by drawing
//     faster, and pads a very short one to Min Cycle so a small shape doesn't run hot.
//   - Record Budget: a shape that comes out over budget is redrawn with a looser curve tolerance
//     and less detail (up to 4 times), so no setting can produce a record count a laser crawls on.
struct Scan { float4 endpoints, color0, color1, timing, meta; };
RWStructuredBuffer<Scan> O : register(u0);

static const uint CAP = 1023;
static const float PPS = 30000;
static const float JUMP_MS = 0.15, JUMP_MS_PER_UNIT = 0.35;
static const float CORNER_COS = 0.5;   // turns sharper than 60 degrees stop at the corner
// A curve is smooth by construction, so it never stops at a corner, and each chord may turn at
// most ~10 degrees at its midpoint: consecutive chords then meet at roughly 20 degrees or less,
// under Laser Out's 30 degree corner-dwell rule. The record budget never loosens this: a curve
// joint over 30 degrees gets Corner Dwell and hitches (ood-labs/sentinel-bugs#168). Without this a tight tip (a Lissajous extreme)
// fits the distance tolerance with two chords meeting at ~105 degrees; the pen stopped there and
// Laser Out blanked the stop, so every tip went dark.
static const float gTurnCos = 0.985;
static float gTolScale = 1;
static bool gSmooth = false;
static const float TAU = 6.28318530718;
// Content is authored for a 16:9 frame: the mapped scan field spans the same 16:9 frame as the
// projection, so x is compressed by 9/16 and a circle drawn here is round on the wall.
static const float ASPECT = 9.0 / 16.0;

static uint gN = 0;
static float gT = 0;
static float2 gPen = 0;
static bool gHasPen = false;
static float2 gFirst = 0;
static float2 gDir = 0;
static bool gHasDir = false;
static float3 gCol = 0;
static float hueAt = 0;     // 0..1 position used by Rainbow colour
// Scan Signal joint flags (timing.z of a lit record: 1 = the joint at its start is smooth, so Laser
// Out gives it no Corner Dwell; 0 = Laser Out judges the turn). Curve chords that continue a curve
// are flagged smooth; straight strokes are left to Laser Out, so letter and polygon corners keep
// their dwell. A cycle that is one closed lit loop flags its header (see finish()).
static float gJoint = 0;
static bool gAnyBlank = false;

float3 hsv(float h) { return saturate(abs(frac(h + float3(0, 2, 1) / 3) * 6 - 3) - 1); }
float3 strokeColour() { return colour_mode < 0.5 ? line_color : hsv(hueAt + _Time * 0.05); }

float2 xf(float2 p)
{
    float a = spin * _Time, c = cos(a), s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y) * size * float2(ASPECT, 1);
}

float litSec(float len) { return len / max(draw_speed, 1e-3) * 1e-3; }
float jumpSec(float len) { return (JUMP_MS + JUMP_MS_PER_UNIT * len) * 1e-3; }

void seg(float2 a, float2 b, float3 c0, float3 c1, bool blank)
{
    if (gN >= CAP) return;
    float len = distance(a, b);
    if (!blank && len < 1e-5) return;
    float dur = blank ? jumpSec(len) : litSec(len);
    Scan s;
    s.endpoints = float4(a, b);
    s.color0 = blank ? float4(0, 0, 0, 1) : float4(saturate(c0), 1);
    s.color1 = blank ? float4(0, 0, 0, 1) : float4(saturate(c1), 1);
    s.timing = float4(gT, dur, blank ? 0 : gJoint, blank ? 1 : 0);
    gAnyBlank = gAnyBlank || blank;
    s.meta = float4(0, 0, 0, 1);
    O[gN + 1] = s;
    gN++;
    gT += dur;
    gPen = b;
}

// The pen, in content units: to point p, lit or blanked.
void pen(float2 p, bool lit)
{
    p = xf(p);
    float3 col = strokeColour();
    if (!gHasPen) { gPen = p; gFirst = p; gHasPen = true; gCol = col; return; }
    float2 d = p - gPen;
    float L = length(d);
    if (L <= (lit ? 1e-5 : 1e-4)) return;
    float2 u = d / L;
    bool corner = lit && gHasDir && !gSmooth && dot(u, gDir) < CORNER_COS;
    gJoint = (lit && gHasDir && gSmooth && !corner) ? 1 : 0;
    [loop] for (int e = corner ? 0 : 1; e < 2; e++)
        seg(gPen, (e == 0) ? gPen : p, gCol, col, e == 0 || !lit);
    gCol = col;
    gHasDir = lit;
    gDir = u;
}
void moveTo(float2 p) { pen(p, false); }
void lineTo(float2 p) { pen(p, true); }

float2 polar(float r, float a) { return r * float2(cos(a), sin(a)); }

// ------------------------------------------------------------------ curves
// Every curved shape is one of these, parameterised over t in 0..1. q carries per-call arguments.
static uint gDetail = 4;
static const uint C_SPIRAL = 0, C_ROSE = 3, C_LISSAJOUS = 4, C_WAVE = 8;

// Coprime frequency pairs, one per detail level. A shared factor (3:6) makes the figure trace
// itself twice. With the phase on x, the figure grows cusps (the beam stops and reverses) at odd
// multiples of pi/(2b), and is most open, with no cusp, at multiples of pi/b.
float2 lissajousRatio()
{
    const float2 r[10] = { float2(2, 3), float2(3, 4), float2(3, 5), float2(4, 5), float2(5, 6),
                           float2(5, 7), float2(6, 7), float2(7, 8), float2(7, 9), float2(8, 9) };
    return r[clamp(gDetail, 1, 10) - 1];
}

float2 curvePoint(uint kind, float4 q, float t)
{
    if (kind == C_SPIRAL) { float turns = 2 + gDetail; return polar(0.95 * t, t * turns * TAU); }
    if (kind == C_ROSE) { float k = 2 + gDetail, a = t * TAU; return polar(0.95 * cos(k * a), a); }
    if (kind == C_LISSAJOUS) { float2 f = lissajousRatio(); float a = t * TAU; return float2(sin(f.x * a + q.x), sin(f.y * a)) * 0.95; }
    // C_WAVE: one line of the sheet, across the frame, at height q.x with phase q.y; q.z = -1 draws
    // it right to left so the sheet is drawn back and forth without a return jump.
    float x = lerp(-0.95, 0.95, q.z > 0 ? t : 1 - t);
    return float2(x, q.x + 0.16 * sin(3.1 * x + q.y) * (0.6 + 0.4 * cos(1.7 * x - q.y * 0.5)));
}

// Largest parameter step per kind, so a chord test can't skip a whole lobe or turn.
float maxStep(uint kind)
{
    if (kind == C_SPIRAL) return 1.0 / (12 * (2 + gDetail));
    if (kind == C_ROSE) return 1.0 / (16 * (2 + gDetail));
    if (kind == C_LISSAJOUS) return 1.0 / (8 * lissajousRatio().y);
    if (kind == C_WAVE) return 1.0 / 12;
    return 1.0 / 24;
}

float chordDist(float2 p, float2 a, float2 b)
{
    float2 d = b - a;
    return length(p - a - d * saturate(dot(p - a, d) / max(dot(d, d), 1e-12)));
}

// Where two chords of a curve may meet: under Laser Out's 30 degree corner-dwell rule, with margin.
// The midpoint test bounds the turn inside each chord; this bounds the joint itself, which a long
// chord (a loosened tolerance) next to a short one can otherwise push past 30 degrees.
static const float JOINT_COS = 0.906;   // 25 degrees

// Does the straight segment t0..t1 stay within Curve Tolerance of the curve (measured in scan units),
// and meet the previous chord (direction pd, zero for the first) at a joint gentle enough to flow?
bool fits(uint kind, float4 q, float t0, float t1, float2 pd)
{
    float2 a = xf(curvePoint(kind, q, t0)), b = xf(curvePoint(kind, q, t1));
    float lc = length(b - a);
    if (lc > 1e-6 && dot(pd, pd) > 0.5 && dot((b - a) / lc, pd) < JOINT_COS) return false;
    float err = 0;
    [unroll] for (int k = 1; k <= 3; k++) err = max(err, chordDist(xf(curvePoint(kind, q, lerp(t0, t1, k * 0.25))), a, b));
    float2 m = xf(curvePoint(kind, q, lerp(t0, t1, 0.5))), u = m - a, v = b - m;
    float lu = length(u), lv = length(v);
    bool gentle = lu < 1e-6 || lv < 1e-6 || dot(u, v) >= gTurnCos * lu * lv;
    return err <= curve_tolerance * gTolScale && gentle;
}

// Adaptive emitter: the fewest segments that stay within tolerance. One lineTo call site.
void emitCurve(uint kind, float4 q, float hue0, float hue1)
{
    hueAt = hue0;
    moveTo(curvePoint(kind, q, 0));
    float cap = maxStep(kind), t = 0, dt = cap * 0.25;
    // A closed curve (rose, Lissajous) meets its own start at the seam, so its first chord must
    // flow from the direction the curve arrives there.
    float2 pd = 0;
    if (kind == C_ROSE || kind == C_LISSAJOUS)
        pd = normalize(xf(curvePoint(kind, q, 0)) - xf(curvePoint(kind, q, 1 - 1e-3)));
    [loop] for (uint g = 0; g < 1024 && t < 1; g++)
    {
        float tn = min(t + dt, 1);
        [loop] for (uint i = 0; i < 8; i++) { float tg = min(t + min((tn - t) * 2, cap), 1); if (tg > tn && fits(kind, q, t, tg, pd)) tn = tg; }
        [loop] for (uint j = 0; j < 12; j++) { if (tn - t > 1e-4 && !fits(kind, q, t, tn, pd)) tn = t + (tn - t) * 0.5; }
        float2 c = xf(curvePoint(kind, q, tn)) - xf(curvePoint(kind, q, t));
        if (length(c) > 1e-6) pd = normalize(c);
        dt = tn - t;
        t = tn;
        hueAt = lerp(hue0, hue1, t);
        gSmooth = true;
        lineTo(curvePoint(kind, q, t));
        gSmooth = false;
    }
}

// ------------------------------------------------------------------ shapes
#include "word_font.hlsli"
void spiral() { emitCurve(C_SPIRAL, 0, 0, 1); }
void rose() { emitCurve(C_ROSE, 0, 0, 1); }
// The phase breathes within half a step of 0, the most open figure, never reaching a cusp at
// pi/(2b), where the beam would stop and reverse (a 180 degree corner that earns a dwell).
void lissajous()
{
    float b = lissajousRatio().y, cusp = 3.14159265 / (2 * b);
    emitCurve(C_LISSAJOUS, float4(cusp * 0.5 * sin(_Time * 0.5), 0, 0, 0), 0, 1);
}

// Many short lit rays with a blank return between each: the blank-heavy worst case. Three records a
// ray, so the ray count also yields to the record budget.
void starburst()
{
    uint rays = min(min(8 * gDetail, 160), max((uint)record_budget / 3, 8));
    for (uint k = 0; k < rays; k++)
    {
        float a = k * TAU / rays + 0.2 * _Time;
        float r = (k & 1) != 0 ? 0.55 : 0.95;
        hueAt = k / (float)rays;
        moveTo(polar(0.08, a));
        lineTo(polar(r, a));
    }
}

// Nested squares flying outward like an infinite zoom, each turned a little more than the one inside
// it: square corners (corner stops) and one blank jump per square.
void tunnel()
{
    uint n = 3 + gDetail;
    float phase = frac(_Time * 0.18);
    for (uint k = 0; k < n; k++)
    {
        float f = frac(phase + k / (float)n);              // 0 at the vanishing point, 1 at the frame
        float r = 0.06 + 0.9 * f * f;
        float a = 0.55 * f + _Time * 0.25;
        hueAt = f;
        [loop] for (uint c = 0; c <= 4; c++)
        {
            float2 p = polar(r * 1.41421356, a + TAU * (c % 4) / 4 + TAU / 8) * float2(1, 0.72);
            if (c == 0) moveTo(p); else lineTo(p);
        }
    }
}

// A sheet of rippling sine lines drawn back and forth, so each line starts where the last ended.
void wave()
{
    uint n = 2 + gDetail / 2 + gDetail % 2;
    for (uint k = 0; k < n; k++)
    {
        float y = lerp(-0.7, 0.7, n > 1 ? k / (float)(n - 1) : 0.5);
        emitCurve(C_WAVE, float4(y, _Time * 1.3 + k * 0.7, (k & 1) != 0 ? -1 : 1, 0), k / (float)n, (k + 1) / (float)n);
    }
}

// SENTINEL in a single-stroke laser font, letters bobbing in a slow wave. Straight strokes with
// sharp corners: the pen stops at each one, the way text wants.
void word()
{
    float s = 1.9 / WORD_W;
    for (uint i = 0; i < WORD_N; i++)
    {
        float4 g = WORD[i];
        float bob = 0.08 * sin(_Time * 2 - g.w * 0.7);
        float2 p = float2((g.x - WORD_W * 0.5) * s, (g.y - 0.5) * s * 1.6 + bob);
        hueAt = g.w / 8;
        if (g.z < 0.5) moveTo(p); else lineTo(p);
    }
}

// A regular polygon morphing through 3..8 sides: one corner splits off another and walks round to
// its new place, so the outline stays one closed stroke the whole way.
void morph()
{
    float span = 5, cyc = _Time * 0.35;
    float pos = cyc - floor(cyc / (2 * span)) * (2 * span);
    float sides = 3 + (pos < span ? pos : 2 * span - pos);       // 3 -> 8 -> 3, ping-pong
    uint n = min((uint)floor(sides), 8u), m = min(n + 1, 8u);
    float blend = n < 8 ? smoothstep(0.2, 0.8, sides - n) : 0;
    float turn = _Time * 0.3;
    [loop] for (uint c = 0; c <= m; c++)
    {
        uint v = c % m;
        // Vertex v of the m-gon; on the n-gon the extra vertex sits on vertex n-1's corner.
        float aFrom = TAU * min(v, n - 1) / n, aTo = TAU * v / m;
        float2 p = polar(0.85, lerp(aFrom, aTo, blend) + turn);
        hueAt = v / (float)m;
        if (c == 0) moveTo(p); else lineTo(p);
    }
}

void drawShape(uint s)
{
    if (s == 0) spiral();
    else if (s == 1) rose();
    else if (s == 2) lissajous();
    else if (s == 3) starburst();
    else if (s == 4) tunnel();
    else if (s == 5) wave();
    else if (s == 6) word();
    else morph();
}

void resetPen() { gN = 0; gT = 0; gPen = 0; gHasPen = false; gFirst = 0; gDir = 0; gHasDir = false; gCol = 0; gJoint = 0; gAnyBlank = false; }

void finish()
{
    if (gHasPen && distance(gPen, gFirst) > 1e-4) seg(gPen, gFirst, 0, 0, true);
    // One closed lit loop (a Lissajous, a rose): no blank anywhere, so the seam is just another
    // point on the curve. Padding below adds a blank and ends that.
    bool closed = gN > 0 && !gAnyBlank;
    float minC = max(min_cycle_ms, 0) * 1e-3;
    if (gN > 0 && gN < CAP && gT < minC)
    {
        closed = false;
        // Pad: a blanked record that stays where the pen is, for the rest of the minimum cycle.
        Scan s;
        s.endpoints = float4(gPen, gPen);
        s.color0 = float4(0, 0, 0, 1); s.color1 = s.color0;
        s.timing = float4(gT, minC - gT, 0, 1);
        s.meta = float4(0, 0, 0, 1);
        O[gN + 1] = s;
        gN++;
        gT = minC;
    }
    float cycle = gT;
    float maxC = max(max_cycle_ms, 1) * 1e-3;
    float k = (cycle > maxC && cycle > 0) ? maxC / cycle : 1.0;
    cycle = (gN > 0) ? cycle * k : 1.0 / 60.0;
    [loop] for (uint i = 1; i <= gN; i++)
    {
        Scan s = O[i];
        s.timing.xy *= k;
        s.meta.z = cycle;
        O[i] = s;
    }
    Scan h = (Scan)0;
    h.endpoints = float4(gN, cycle, PPS, 0);
    h.timing.z = closed ? 1 : 0;
    h.meta = float4(0, 0, 0, 1);
    O[0] = h;
    [loop] for (uint z = gN + 1; z <= CAP; z++) O[z] = (Scan)0;
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint s = (uint)shape;
    if (s >= 8) s = (uint)floor(_Time / max(cycle_seconds, 0.5)) % 8;   // Cycle All
    uint detail0 = (uint)clamp(detail, 1, 10);
    // Record budget: redraw looser and simpler until the shape fits (4 tries).
    [loop] for (uint attempt = 0; attempt < 4; attempt++)
    {
        resetPen();
        gTolScale = exp2((float)attempt);
        gDetail = max(1u, (detail0 * (4 - attempt)) / 4);
        drawShape(s);
        if (gN <= (uint)max(record_budget, 16)) break;
    }
    finish();
}
