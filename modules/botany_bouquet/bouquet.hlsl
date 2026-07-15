// botany_bouquet — a flat-color "riso/pop" botanical bouquet on a violet ground, in the
// visual language of the reference clip x8X82M4fonC5rKXl: striped hatched blade-leaves,
// mosaic berry clusters, dotted hydrangea spheres, drooping line-hatched petals, black
// wire scribbles, and a translucent brighter-violet crop-frame with a tiny caption row.
// Single 2D compute pixel pass, painter's-algorithm back-to-front (dada_totem pattern in 2D).
// Slow seamless push-in + drift via anim.hlsli. Display-space output (no gamma pow).
#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// ---------- helpers ----------
float h11(float p){ p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float h21(float2 p){ float3 p3 = frac(float3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return frac((p3.x + p3.y) * p3.z); }
float2 rot2(float2 v, float a){ float c = cos(a), s = sin(a); return float2(c*v.x - s*v.y, s*v.x + c*v.y); }
float sdSeg(float2 p, float2 a, float2 b){ float2 pa=p-a, ba=b-a; float h=saturate(dot(pa,ba)/dot(ba,ba)); return length(pa-ba*h); }
float sdBezier2(float2 p, float2 a, float2 b, float2 c){
    float d=1e9; float2 prev=a;
    [unroll] for(int i=1;i<=12;i++){ float t=(float)i/12.0; float2 pt=lerp(lerp(a,b,t),lerp(b,c,t),t); d=min(d,sdSeg(p,prev,pt)); prev=pt; }
    return d;
}
void paint(inout float3 col, float3 c, float a){ col = lerp(col, c, saturate(a)); }
float stripeLine(float x, float freq, float w){ float f = frac(x*freq); return smoothstep(w, 0.0, min(f, 1.0-f)); }

// ---------- palette (display-space, read off the reference) ----------
static const float3 BG_VIOLET    = float3(0.42, 0.28, 0.75);
static const float3 FRAME_VIOLET = float3(0.52, 0.16, 0.90);
static const float3 FRAME_LINE   = float3(0.09, 0.05, 0.20);
static const float3 RED          = float3(0.92, 0.16, 0.10);
static const float3 ORANGE       = float3(0.97, 0.48, 0.10);
static const float3 YELLOW       = float3(1.00, 0.86, 0.10);
static const float3 GREEN_A      = float3(0.52, 0.78, 0.20);
static const float3 GREEN_B      = float3(0.86, 0.90, 0.20);
static const float3 BERRY_O      = float3(0.97, 0.46, 0.10);
static const float3 BERRY_R      = float3(0.86, 0.13, 0.09);
static const float3 BERRY_DK     = float3(0.34, 0.05, 0.28);
static const float3 GREY_L       = float3(0.66, 0.70, 0.80);
static const float3 GREY_D       = float3(0.38, 0.43, 0.58);
static const float3 PINK         = float3(0.98, 0.60, 0.68);
static const float3 SALMON       = float3(0.95, 0.55, 0.50);
static const float3 CYAN         = float3(0.28, 0.86, 0.80);
static const float3 BLUE         = float3(0.22, 0.34, 0.92);
static const float3 MAGENTA      = float3(0.86, 0.20, 0.62);
static const float3 NAVY         = float3(0.04, 0.03, 0.11);

// ---------- a curved striped blade leaf ----------
void drawLeaf(inout float3 col, float2 q, float2 c, float ang, float L, float W,
              float3 bodyA, float3 bodyB, float stripeFreq, float stripeAmt, float curve, float aa)
{
    float2 d = rot2(q - c, -ang);
    float yn = d.y / (L*0.5);                       // -1 tip(up) .. +1 base
    if (abs(yn) >= 1.0) return;
    float cxl = curve * yn * L * 0.42;              // banana centerline bend
    float xr = d.x - cxl;
    float prof = pow(saturate(1.0 - yn*yn), 0.48);  // broad tongue
    float halfW = W*0.5*prof;
    float edge = smoothstep(0.0, aa*1.5, halfW - abs(xr));
    float ends = smoothstep(0.0, aa*1.5, 1.0 - abs(yn));
    float mask = edge*ends;
    if (mask <= 0.0) return;
    float tlen = 0.5 - 0.5*yn;                       // 0 base .. 1 tip
    float3 body = lerp(bodyA, bodyB, tlen);
    // fine lengthwise veins + bright midrib
    float lin = stripeLine(xr, stripeFreq, 0.010);
    float rib = smoothstep(0.007, 0.002, abs(xr));
    body = lerp(body, YELLOW, saturate(max(lin*stripeAmt, rib)));
    // dark rim outline
    float rim = smoothstep(aa*1.5, aa*3.4, halfW - abs(xr));
    body = lerp(FRAME_LINE, body, saturate(rim + 0.12));
    paint(col, body, mask);
}

// ---------- broad drooping hatched petal ----------
void drawPetal(inout float3 col, float2 q, float2 c, float ang, float L, float W,
               float3 ca, float3 cb, float bend, float hatchFreq, float aa)
{
    float2 d = rot2(q - c, -ang);
    float yn = d.y / (L*0.5);
    if (abs(yn) >= 1.0) return;
    d.x -= bend * (yn*yn) * L * 0.5;
    float prof = pow(saturate(1.0 - yn*yn), 0.40);
    float halfW = W*0.5*prof;
    float edge = smoothstep(0.0, aa*1.5, halfW - abs(d.x));
    float ends = smoothstep(0.0, aa*1.5, 1.0 - abs(yn));
    float mask = edge*ends;
    if (mask <= 0.0) return;
    float3 body = lerp(ca, cb, saturate(0.5 - 0.5*yn + d.x/max(W,0.001)*0.4));
    // contour hatch lines running across the width (follow the form)
    float lin = stripeLine(d.y + d.x*0.15, hatchFreq, 0.018);
    body = lerp(body, body*0.5, lin*0.7);
    float rim = smoothstep(aa*1.5, aa*3.6, halfW - abs(d.x));
    body = lerp(FRAME_LINE, body, saturate(rim + 0.18));
    paint(col, body, mask);
}

// ---------- mosaic berry cluster ----------
void drawBerry(inout float3 col, float2 q, float2 c, float R, float cellFreq, float seed, float aa)
{
    float2 local = q - c;
    float r = length(local);
    float disc = smoothstep(R, R-aa*2.0, r);
    if (disc <= 0.0) return;
    float2 cell = local * cellFreq;
    float2 id = floor(cell);
    float2 jit = (float2(h21(id+seed), h21(id+seed+13.7)) - 0.5) * 0.55;
    float2 f = frac(cell) - 0.5 - jit;               // irregular packed drupelets
    float rnd = h21(id + seed);
    float dsq = length(f) * (0.80 + 0.4*rnd);
    float cm = smoothstep(0.50, 0.26, dsq);
    float3 cc = lerp(BERRY_R, BERRY_O, rnd*rnd);      // biased toward red
    float3 body = lerp(BERRY_DK, cc, cm);
    body *= 0.60 + 0.44*saturate(1.0 - r/R);
    body = lerp(FRAME_LINE, body, saturate(smoothstep(aa*1.5, aa*3.5, R-r) + 0.15));
    paint(col, body, disc);
}

// ---------- dotted hydrangea sphere ----------
void drawSphere(inout float3 col, float2 q, float2 c, float R, float dotFreq, float aa)
{
    float2 local = q - c;
    float r = length(local);
    float disc = smoothstep(R, R-aa*2.0, r);
    if (disc <= 0.0) return;
    float2 g = frac(local*dotFreq) - 0.5;
    float dt = smoothstep(0.26, 0.14, length(g));
    float3 body = lerp(GREY_L, GREY_D, dt);
    body *= 0.66 + 0.40*saturate(1.0 - r/R);
    body = lerp(FRAME_LINE, body, saturate(smoothstep(aa*1.5, aa*3.5, R-r) + 0.2));
    paint(col, body, disc);
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float aspect = res.x / res.y;
    float2 uv = ((float2)px + 0.5) / res;
    float2 q  = uv * float2(aspect, 1.0);
    float aa  = 1.4 / res.y;
    float cx  = aspect * 0.5;

    // ---- animation: seamless push-in + drift ----
    float period = max(loop_period, 0.001);
    float ph = frac(_Time / period);
    float breath = 0.5 - 0.5*cos(ph * AN_TAU);
    float zoom = 1.0 + zoom_amt * breath;
    float2 drift = float2(an_loop_noise(_Time, period, 1.0, 3.0),
                          an_loop_noise(_Time, period, 1.0, 7.0)) * drift_amt;
    float2 pivot = float2(cx, 0.52);
    float2 qb = (q - pivot) / zoom + pivot + drift;

    float2 fdrift = float2(an_loop_noise(_Time, period, 1.0, 11.0),
                           an_loop_noise(_Time, period, 1.0, 17.0)) * drift_amt * 0.6;

    float3 col = BG_VIOLET;

    // ---- crop frame fill (behind bouquet) ----
    float2 fq = q - fdrift;
    float fx0 = frame_x0*aspect, fx1 = frame_x1*aspect, fy0 = frame_y0, fy1 = frame_y1;
    float insideX = step(fx0, fq.x) * step(fq.x, fx1);
    float insideY = step(fy0, fq.y) * step(fq.y, fy1);
    paint(col, FRAME_VIOLET, insideX*insideY * frame_fill);

    // ================= BOUQUET (back → front), asymmetric & dense =================
    float2 base = float2(cx*1.05, 0.60);

    // ---- back scatter leaves (density, darker) ----
    [loop] for (int b = 0; b < 14; b++)
    {
        float r1=h11(b*3.1+1.3), r2=h11(b*7.3+2.7), r3=h11(b*5.7+3.9), r4=h11(b*2.9+4.5);
        float ang = (r1-0.42)*1.7;
        float2 c = base + float2((r2-0.45)*0.34, -0.06 - r3*0.30);
        float L = 0.32 + r4*0.30;
        float W = 0.040 + r1*0.050;
        float3 ca = lerp(RED*0.80, ORANGE*0.82, r2);
        float3 cb = lerp(ORANGE*0.85, YELLOW*0.70, r3);
        if (r4 > 0.82) { ca = GREEN_A*0.8; cb = GREEN_B*0.8; W *= 0.6; }
        drawLeaf(col, qb, c, ang, L, W, ca, cb, 150.0, 0.5, (r1-0.5)*1.0, aa);
    }

    // ---- green blades shooting up ----
    drawLeaf(col, qb, base+float2(-0.06,-0.10), -0.10, 0.66, 0.045, GREEN_A, GREEN_B, 120.0, 0.5,  0.10, aa);
    drawLeaf(col, qb, base+float2(-0.13,-0.04), -0.42, 0.52, 0.038, GREEN_A, GREEN_B, 120.0, 0.5, -0.45, aa);
    drawLeaf(col, qb, base+float2( 0.10,-0.06),  0.30, 0.50, 0.040, GREEN_A, GREEN_B, 120.0, 0.5,  0.40, aa);

    // ---- hero red/orange blades (bold, leaning, fanning) ----
    const int NH = 10;
    float2 hoff[NH] = { float2(-0.03,-0.02), float2( 0.04,-0.03), float2(-0.08, 0.00), float2( 0.09,-0.01),
                        float2( 0.01,-0.04), float2(-0.12, 0.02), float2( 0.13, 0.01), float2(-0.02, 0.01),
                        float2( 0.06,-0.02), float2(-0.06,-0.01) };
    float hang[NH]  = { -0.28, -0.10,  0.14,  0.30, -0.02,  0.46, -0.40,  0.06,  0.22, -0.20 };
    float hlen[NH]  = {  0.64,  0.68,  0.60,  0.56,  0.66,  0.50,  0.52,  0.62,  0.54,  0.58 };
    float hwid[NH]  = {  0.100, 0.110, 0.095, 0.088, 0.105, 0.072, 0.078, 0.100, 0.084, 0.092 };
    [loop] for (int h = 0; h < NH; h++)
    {
        float2 c = base + hoff[h] + float2(0.0, -hlen[h]*0.42);
        drawLeaf(col, qb, c, hang[h], hlen[h], hwid[h], RED, ORANGE, 160.0, 0.85, hang[h]*1.3, aa);
    }

    // ---- mid: dotted spheres (left) + mosaic berries (center-right) ----
    drawSphere(col, qb, base+float2(-0.15, 0.03), 0.072, 62.0, aa);
    drawSphere(col, qb, base+float2(-0.10, 0.12), 0.052, 74.0, aa);
    drawSphere(col, qb, base+float2( 0.02, 0.10), 0.040, 80.0, aa);
    drawBerry (col, qb, base+float2( 0.13,-0.05), 0.060, 46.0, 2.1, aa);
    drawBerry (col, qb, base+float2( 0.16, 0.06), 0.068, 42.0, 5.7, aa);
    drawBerry (col, qb, base+float2( 0.07, 0.03), 0.046, 52.0, 8.3, aa);
    drawBerry (col, qb, base+float2( 0.19,-0.02), 0.042, 50.0, 3.4, aa);

    // ---- black wire scribbles (thin, angular, woven) ----
    float sw = 0.0032;
    float2 w0[4] = { base+float2(-0.12,-0.01), base+float2(-0.01,0.07), base+float2(0.09,-0.03), base+float2(0.17,0.05) };
    float2 w1[4] = { base+float2(-0.07,0.11),  base+float2(0.04,-0.04), base+float2(0.12,0.08), base+float2(0.20,-0.02) };
    float2 w2[4] = { base+float2(-0.15,0.07),  base+float2(-0.04,0.01), base+float2(0.06,0.11), base+float2(0.14,0.02) };
    [unroll] for (int s = 0; s < 3; s++) {
        paint(col, NAVY, smoothstep(sw+aa, sw, sdSeg(qb, w0[s], w0[s+1])));
        paint(col, NAVY, smoothstep(sw+aa, sw, sdSeg(qb, w1[s], w1[s+1])));
        paint(col, NAVY, smoothstep(sw+aa, sw, sdSeg(qb, w2[s], w2[s+1])));
    }

    // ---- front: drooping hatched petals massed lower-left ----
    drawPetal(col, qb, base+float2(-0.17, 0.16), -1.0, 0.32, 0.14, SALMON, PINK,  0.40, 80.0, aa);
    drawPetal(col, qb, base+float2(-0.12, 0.22), -0.6, 0.30, 0.13, PINK,   CYAN,  0.34, 90.0, aa);
    drawPetal(col, qb, base+float2(-0.20, 0.09), -1.3, 0.26, 0.11, SALMON, MAGENTA,0.48, 80.0, aa);
    drawPetal(col, qb, base+float2(-0.05, 0.24), -0.2, 0.30, 0.13, CYAN,   BLUE,  0.16, 90.0, aa);
    drawPetal(col, qb, base+float2( 0.05, 0.24),  0.2, 0.30, 0.14, PINK,   BLUE,  0.02, 80.0, aa);
    drawPetal(col, qb, base+float2( 0.14, 0.21),  0.6, 0.28, 0.12, ORANGE, YELLOW,-0.28, 70.0, aa);
    drawPetal(col, qb, base+float2(-0.24, 0.18), -1.5, 0.22, 0.10, PINK,   SALMON, 0.55, 80.0, aa);

    // ---- crop frame outline + tiny caption (on top) ----
    float distL = min(min(abs(fq.x-fx0), abs(fq.x-fx1)), min(abs(fq.y-fy0), abs(fq.y-fy1)));
    float border = smoothstep(0.0020, 0.0, distL) *
                   step(fx0-0.004, fq.x)*step(fq.x, fx1+0.004)*step(fy0-0.004, fq.y)*step(fq.y, fy1+0.004);
    paint(col, FRAME_LINE, border);
    [loop] for (int t = 0; t < 8; t++)
    {
        float2 cpos = float2(fx0 + 0.012 + t*0.006, fy1 - 0.016);
        float2 cd = abs(fq - cpos);
        paint(col, FRAME_LINE, step(cd.x, 0.0016) * step(cd.y, 0.005));
    }

    OutputUAV[px] = float4(saturate(col), 1.0);
}
