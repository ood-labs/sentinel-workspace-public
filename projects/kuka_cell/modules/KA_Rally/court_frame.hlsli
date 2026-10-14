// KA_Rally / court_frame.hlsli — the court instrument's geometry: ONE function of the live extent
// and the cell's declared size, called by the drawing (court.hlsl) and the type (layout.hlsl), so a
// player, its reach ring, a caption and the hover test all sit on the same metres-to-pixels map.
//
//   title row
//   COURT PLAN (one isotropic scale, so a reach circle is a circle)   |  PLAY pane
//   FLIGHT PROFILE, forward-looking, aligned under the court          |
//   keycap footer and legend
#ifndef KA_COURT_FRAME_HLSLI
#define KA_COURT_FRAME_HLSLI

#define CT_SPAN_S 4.0          // seconds of predicted flight the profile shows

struct CtFrame
{
    float  s;          // ui scale (1 at the 1024 x 640 reference)
    float4 head;       // the title row
    float4 court;      // the court plate
    float4 fly;        // the flight profile plate
    float4 plot;       // its plot: x is seconds ahead (0 .. CT_SPAN_S), y is height, floor at plot.w
    float4 side;       // the PLAY pane column
    float4 foot;       // the keycap footer
    float2 planC;      // the court's centre, px
    float  ppm;        // court pixels per metre
};

CtFrame ctFrame(float2 R, float cw, float cd)
{
    CtFrame F;
    float s = kaUiScale(R);
    F.s = s;
    float4 r = float4(16.0 * s, 0.0, R.x - 16.0 * s, R.y - 6.0 * s);
    F.head = ilCutTop(r, 34.0 * s);
    F.foot = ilCutBottom(r, 30.0 * s);
    F.side = ilCutRight(r, clamp((r.z - r.x) * 0.25, 220.0 * s, 330.0 * s));
    r.z -= 10.0 * s;
    F.fly = ilCutBottom(r, clamp((r.w - r.y) * 0.17, 70.0 * s, 130.0 * s));
    r.w -= 8.0 * s;
    F.court = r;
    F.plot = float4(F.fly.x + 94.0 * s, F.fly.y + 8.0 * s, F.fly.z - 10.0 * s, F.fly.w - 9.0 * s);
    float4 fit = ilInset(F.court, 6.0 * s);
    F.ppm = min((fit.z - fit.x) / max(cw, 4.0), (fit.w - fit.y) / max(cd, 4.0));
    F.planC = ilMid(F.court);
    return F;
}

float2 ctPlanPx(CtFrame F, float2 xz) { return F.planC + xz * F.ppm; }

// TRUE horizontal reach at the strike plane: the radius the election tests a predicted contact
// against, drawn as each player's reach ring (it used to be 0.88 x the headline reach, which is up
// to a fifth too generous once the strike plane is above the shoulder). This mirrors rally.hlsl's
// playReach (same spec, same strike height, same 0.92 margin); the rally pass is the authority and
// stays untouched, so a change to one must be made to the other.
float ctPlayReach(KaRec r)
{
    KaSpec sp = ka_spec(r.kind, r.size.x);
    float R = sp.l2 + sp.l3 + sp.l4;
    float dy = abs(strike_h - (r.size.y + sp.turret));
    if (dy >= R) return 0.0;
    return (sp.off1 + sqrt(R * R - dy * dy)) * 0.92;
}

// Flight profile: seconds ahead -> x, metres up -> y. hmax keeps the strike plane in the lower half.
float ctHMax() { return max(strike_h * 2.2, 4.0); }
float ctFlyX(CtFrame F, float t) { return lerp(F.plot.x, F.plot.z, saturate(t / CT_SPAN_S)); }
float ctFlyY(CtFrame F, float h) { return lerp(F.plot.w, F.plot.y, saturate(h / ctHMax())); }

#endif
