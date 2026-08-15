// FM_Scope / marks.hlsl — every instrument mark, as one draw call.
//
// Each mark is a world-space SEGMENT expanded into a screen-space quad in the vertex shader, so
// a hairline is a hairline at any distance and the whole overlay is one pass. The alternative —
// a per-pixel loop over three thousand segments — is a frame-rate cliff, and hardware line
// topology gives no width control at all.
//
// OCCLUSION IS MANUAL, against FM_Render's published linear depth. This node has no depth
// buffer of its own and does not want one: it must hide behind the SAME geometry the beauty
// image shows, and the only honest source for that is the depth lane the renderer produced from
// the same camera. Marks that fail the test are attenuated rather than discarded — a fully
// hidden overlay reads as broken, while a faint one reads as an instrument seen through the
// subject.
#include "../_shared/formic.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "scope.hlsli"

// ---------------------------------------------------------------------------
// A LIGHT-GROUND INK SET, and the reason it exists.
//
// The shared instrument palette is built for a near-black canvas: PT_INK is near white, because
// on a dark ground the brightest mark is the most present one. This overlay does not sit on a
// dark ground. It sits on a blown-out white studio sweep, where near-white ink is invisible and
// mid grey reads as the loudest thing in the frame — the value ladder is inverted end to end.
//
// So the ladder is inverted here rather than the palette being ignored. The STRUCTURE is
// identical to plan_theme's and the roles are the same ones by the same names — ink for a
// measurement, rule for something faint, accent reserved for a live reading, alarm reserved for
// broken — only the direction of "more present" is flipped, and the two reserved hues are
// darkened so they still separate from white.
// ---------------------------------------------------------------------------
#define SC_INK    float3(0.090, 0.092, 0.100)   // primary: recorded measurement
#define SC_MID    float3(0.330, 0.335, 0.345)   // secondary plotted data
#define SC_RULE   float3(0.560, 0.565, 0.575)   // faint: a prediction, a guess
#define SC_GRID   float3(0.660, 0.665, 0.670)   // background structure
#define SC_ACCENT float3(0.860, 0.330, 0.020)   // RESERVED: live reading
#define SC_ALARM  float3(0.800, 0.060, 0.120)   // RESERVED: broken

// Identity, for the three gizmo axes — a small closed unordered set with nothing in the shape
// to tell its members apart. Darkened from the shared muted set for the same reason as above.
float3 scAxis(int i)
{
    int k = ((i % 3) + 3) % 3;
    if (k == 0) return float3(0.72, 0.20, 0.16);   // forward
    if (k == 1) return float3(0.16, 0.44, 0.24);   // up
    return float3(0.16, 0.30, 0.62);               // right
}

StructuredBuffer<FmRec>     PlanB : register(t0);
StructuredBuffer<FmAnt>     Ants  : register(t1);
StructuredBuffer<FmFoot>    Feet  : register(t2);
StructuredBuffer<FmTrailPt> Trail : register(t3);
StructuredBuffer<FmSCtl>    SCtl  : register(t4);
// _Tex5 — FM_Render's linear depth. _Tex6 — the pheromone field.

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float3 Colour   : COLOR0;
    // x = eye depth (mm), y = coverage/alpha, z = dash phase (<0 means solid)
    float3 Extra    : TEXCOORD0;
};

VS_OUTPUT degenerate()
{
    VS_OUTPUT o;
    o.Position = float4(0, 0, -999, 1);
    o.Colour = 0; o.Extra = float3(1, 0, -1);
    return o;
}

// Expand a world segment into a screen-space quad `widthPx` wide.
VS_OUTPUT emitSeg(float3 A, float3 B, uint corner, float3 col, float widthPx, float dash)
{
    VS_OUTPUT o;
    float4 ca = mul(_ViewProjMatrix, float4(A, 1.0));
    float4 cb = mul(_ViewProjMatrix, float4(B, 1.0));
    // Behind the eye: there is no sensible screen-space expansion of a segment that crosses the
    // camera plane, and clamping w produces a mark that whips across the frame.
    if (ca.w < 1e-3 || cb.w < 1e-3) return degenerate();

    float2 na = ca.xy / ca.w;
    float2 nb = cb.xy / cb.w;

    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 d = (nb - na) * float2(aspect, 1.0);
    float dl = length(d);
    if (dl < 1e-7) return degenerate();
    d /= dl;

    float2 p = float2(-d.y, d.x);
    p.x /= aspect;
    // One pixel is 2/res.y of NDC vertically.
    float2 off = p * (widthPx / max(_Resolution.y, 1.0));

    // Two triangles: (0,-1) (1,-1) (1,+1) and (0,-1) (1,+1) (0,+1)
    float t, s;
    if (corner == 0u)      { t = 0.0; s = -1.0; }
    else if (corner == 1u) { t = 1.0; s = -1.0; }
    else if (corner == 2u) { t = 1.0; s =  1.0; }
    else if (corner == 3u) { t = 0.0; s = -1.0; }
    else if (corner == 4u) { t = 1.0; s =  1.0; }
    else                   { t = 0.0; s =  1.0; }

    float2 ndc = lerp(na, nb, t) + off * s;
    o.Position = float4(ndc, 0.5, 1.0);
    o.Colour = col;
    o.Extra = float3(lerp(ca.w, cb.w, t), 1.0, dash < 0.0 ? -1.0 : (dash + t * 40.0));
    return o;
}

VS_OUTPUT VSMain(uint vid : SV_VertexID)
{
    uint seg = vid / 6u;
    uint corner = vid - seg * 6u;
    if (seg >= SEG_TOTAL) return degenerate();

    FmRec arena = PlanB[FM_ARENA];
    FmSCtl ctl = SCtl[0];
    float ex = saturate(explode);

    // ---- GIZMOS. The ant's real heading frame: forward, up, right, built from the SAME
    // vectors the renderer builds the body in, so it reports the actual orientation rather than
    // a second guess at it.
    if (seg < SEG_PRED_0)
    {
        uint s = seg - SEG_GIZMO_0;
        uint ai = s / 3u;
        uint axis = s - ai * 3u;
        FmAnt a = Ants[ai];
        if (a.active < 0.5 || show_gizmo < 0.5) return degenerate();

        float3 F = normalize(float3(a.dir.x, 0.0, a.dir.z) + float3(1e-5, 0, 0));
        float3 U = float3(0, 1, 0);
        float3 R = normalize(cross(U, F));
        float3 dir = (axis == 0u) ? F : ((axis == 1u) ? U : R);

        float3 base = a.pos + float3(0, LAY_GIZMO * ex, 0);
        float len = gizmo_size * a.size;
        // IDENTITY hue, and one of the four uses the palette permits by name: three axes, no
        // natural order, and nothing in the shape to tell them apart.
        return emitSeg(base, base + dir * len, corner, scAxis((int)axis), line_width * 1.15, -1.0);
    }

    // ---- PREDICTED PATH. An extrapolation, NOT a re-simulation: the measured speed carried
    // forward along a heading that keeps turning at the measured yaw rate. It is honest for
    // about a second and diverges after, which is exactly why it is drawn DASHED and dimmer
    // than the recorded trail beside it — the two must never be mistaken for each other.
    if (seg < SEG_TRAIL_0)
    {
        uint s = seg - SEG_PRED_0;
        uint ai = s / 8u;
        uint k = s - ai * 8u;
        FmAnt a = Ants[ai];
        if (a.active < 0.5 || show_pred < 0.5 || a.speed < 0.05) return degenerate();

        float span = max(pred_time, 0.01);
        float t0 = (float)k / 8.0 * span;
        float t1 = (float)(k + 1u) / 8.0 * span;

        float th0 = atan2(a.dir.z, a.dir.x) + a.turn * t0;
        float th1 = atan2(a.dir.z, a.dir.x) + a.turn * t1;

        // Integrated along the arc rather than stepped from the current heading, so a turning
        // ant's forecast is a curve instead of a straight line with a kink in it.
        float3 p0 = a.pos, p1 = a.pos;
        for (uint i = 0u; i <= k; i++)
        {
            float ta = (float)i / 8.0 * span;
            float tb = (float)(i + 1u) / 8.0 * span;
            float th = atan2(a.dir.z, a.dir.x) + a.turn * ta;
            float3 stepv = float3(cos(th), 0, sin(th)) * a.speed * (tb - ta);
            if (i < k) { p0 += stepv; p1 = p0; }
            else       { p1 = p0 + stepv; }
        }
        float3 lift = float3(0, LAY_PRED * ex, 0);
        float fade = 1.0 - (float)k / 9.0;
        return emitSeg(p0 + lift, p1 + lift, corner, SC_RULE * (1.35 - 0.45 * fade),
                       line_width * 0.95, (float)k * 40.0);
    }

    // ---- MEASURED TRAIL. Recorded history, not a curve fitted after the fact.
    if (seg < SEG_FOOT_0)
    {
        uint s = seg - SEG_TRAIL_0;
        uint ai = s / (SC_TRAIL_LEN - 1u);
        uint k = s - ai * (SC_TRAIL_LEN - 1u);
        FmAnt a = Ants[ai];
        if (a.active < 0.5 || show_trail < 0.5) return degenerate();

        uint cursor = (uint)max(ctl.writeIdx, 0.0) % SC_TRAIL_LEN;
        // Bounded at N-1. Walking back N slots gives N-1 consecutive pairs; the Nth joins the
        // OLDEST sample directly to the NEWEST and draws a chord across the entire trail.
        uint i0 = (cursor + SC_TRAIL_LEN - 1u - k) % SC_TRAIL_LEN;
        uint i1 = (cursor + SC_TRAIL_LEN - 2u - k) % SC_TRAIL_LEN;

        FmTrailPt A = Trail[ai * SC_TRAIL_LEN + i0];
        FmTrailPt B = Trail[ai * SC_TRAIL_LEN + i1];
        // Validated by TIMESTAMP ORDER rather than ring index: a never-written slot has w <= 0,
        // and a pair whose times run backwards is the wrap seam however the indices came out.
        if (A.w <= 0.0 || B.w <= 0.0 || A.w <= B.w) return degenerate();

        float3 lift = float3(0, LAY_TRAIL * ex, 0);
        float fade = 1.0 - (float)k / (float)(SC_TRAIL_LEN - 1u) * saturate(trail_fade);
        return emitSeg(A.pos + lift, B.pos + lift, corner, lerp(SC_MID, SC_INK, fade), line_width, -1.0);
    }

    // ---- FOOT CONTACTS. A short cross arm at every PLANTED tarsus, red where that foot is
    // measured to be scuffing. This is the same slip number the colony's gait chart plots, put
    // back on the ant it belongs to.
    if (seg < SEG_LINK_0)
    {
        uint s = seg - SEG_FOOT_0;
        uint ai = s / FM_LEGS;
        uint lg = s - ai * FM_LEGS;
        FmAnt a = Ants[ai];
        if (a.active < 0.5 || show_feet < 0.5) return degenerate();
        FmFoot f = Feet[ai * FM_LEGS + lg];
        if (f.stance < 0.5) return degenerate();

        float r = a.size * 0.16;
        float3 c = f.pos + float3(0, 0.05, 0);
        bool slipping = f.slip > slip_alarm;
        return emitSeg(c - float3(r, 0, 0), c + float3(r, 0, 0), corner,
                       slipping ? SC_ALARM : SC_MID, line_width * (slipping ? 1.5 : 0.9), -1.0);
    }

    // ---- ANTENNATION. A link between an ant and its nearest neighbour while they are actually
    // in contact. Drawn in the ACCENT because it is a live reading — something happening now,
    // not a property of the arrangement.
    if (seg < SEG_GRAD_0)
    {
        uint ai = seg - SEG_LINK_0;
        FmAnt a = Ants[ai];
        if (a.active < 0.5 || show_link < 0.5 || a.contact < 0.08) return degenerate();

        float best = 1e9; uint bj = 0xffffffffu;
        for (uint j = 0u; j < FM_MAX_ANTS; j++)
        {
            if (j == ai) continue;
            FmAnt b = Ants[j];
            if (b.active < 0.5) continue;
            float d = length(b.pos - a.pos);
            if (d < best) { best = d; bj = j; }
        }
        if (bj == 0xffffffffu) return degenerate();
        // Drawn once per pair, not twice: the lower index owns the link. Drawing both makes
        // every contact twice as bright as a single one and the pairs stop being comparable.
        if (bj < ai) return degenerate();

        float3 lift = float3(0, LAY_GIZMO * ex * 0.35, 0);
        return emitSeg(a.pos + lift, Ants[bj].pos + lift, corner,
                       SC_ACCENT * saturate(0.55 + a.contact * 0.9), line_width * 1.1, -1.0);
    }

    // ---- THE FIELD THE ANTS ARE STEERING ON. A gradient probe on a regular grid: each stub
    // points the way the food scent increases, which is the direction an outbound ant is being
    // pulled. Without it the trail-following looks like magic; with it the mechanism is visible.
    {
        uint s = seg - SEG_GRAD_0;
        if (show_grad < 0.5) return degenerate();
        uint gx = s % SEG_GRAD_NX;
        uint gy = s / SEG_GRAD_NX;

        float2 ahalf = fmArenaHalf(arena);
        float2 uv = float2(((float)gx + 0.5) / (float)SEG_GRAD_NX,
                           ((float)gy + 0.5) / (float)SEG_GRAD_NY);
        float2 w = (uv * 2.0 - 1.0) * ahalf;

        float e = max(ahalf.x, ahalf.y) / 90.0;
        float c0 = _Tex6.SampleLevel(LinearSampler, fmWorldToFieldUV(w + float2(e, 0), arena), 0).r
                 - _Tex6.SampleLevel(LinearSampler, fmWorldToFieldUV(w - float2(e, 0), arena), 0).r;
        float c1 = _Tex6.SampleLevel(LinearSampler, fmWorldToFieldUV(w + float2(0, e), arena), 0).r
                 - _Tex6.SampleLevel(LinearSampler, fmWorldToFieldUV(w - float2(0, e), arena), 0).r;

        float2 g = float2(c0, c1);
        float gl = length(g);
        // Below a floor the gradient is numerical noise and drawing it would carpet the arena
        // with stubs pointing in random directions, which says the opposite of the truth.
        if (gl < 1e-4) return degenerate();

        float len = min(gl * grad_scale, max(ahalf.x, ahalf.y) / (float)SEG_GRAD_NX * 1.6);
        float3 A = float3(w.x, LAY_GRAD * ex, w.y);
        float3 B = A + float3(g.x / gl * len, 0, g.y / gl * len);
        return emitSeg(A, B, corner, SC_GRID, line_width * 0.8, -1.0);
    }
}

float4 PSMain(VS_OUTPUT In) : SV_TARGET
{
    // Dashes, for the predicted path only. A dash pattern is a value-free way to say "this is a
    // guess", which leaves the accent and the alarm free for things that are not.
    if (In.Extra.z >= 0.0 && frac(In.Extra.z * 0.5) > 0.55) discard;

    float2 uv = In.Position.xy / _Resolution.xy;
    float sceneZ = _Tex5.SampleLevel(PointSampler, uv, 0).r;

    // A small bias, or a mark lying exactly on the surface it describes — a foot cross on the
    // ground, a gizmo root on a body — z-fights with it and stipples.
    float vis = (In.Extra.x <= sceneZ + 0.35) ? 1.0 : saturate(occlude);

    // The gain scales COVERAGE, not colour. On a light ground the inks are dark, and
    // multiplying a dark ink by a gain above one makes the mark FAINTER — the opposite of what
    // a control called "Line Gain" should do.
    return float4(In.Colour, saturate(vis * line_gain));
}
