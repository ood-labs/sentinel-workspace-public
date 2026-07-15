// sdf_botany.hlsli — botanical SDF vocabulary for the "Botany Bouquet" recreation
// (ref x8X82M4fonC5rKXl): tapered striped blade-leaves, cupped tulip petals, protea/pinecone
// cones, blended berry clusters, wire-tangle tubes and curling stamens. Every form is a canonical
// local-space SDF (grows +Y from origin); the caller rotates/places it. Requires sdf_ops.hlsli and
// sdf_extras.hlsli included FIRST. No nested includes.
#ifndef SDF_BOTANY_HLSLI
#define SDF_BOTANY_HLSLI

// non-uniform scale of an SDF point: evaluate prim(p/k) then multiply distance by min(k).
// (helper is inline at call sites where needed.)

// tapered, bent, flattened BLADE leaf in local space: base at y=0, tip at y=len.
// halfwid = half width at the belly, thick = half thickness (z), curve = tip bend in +x.
float bb_blade(float3 p, float len, float halfwid, float thick, float curve)
{
    float y  = clamp(p.y, 0.0, len);
    float t  = y / max(len, 1e-4);                       // 0 base .. 1 tip
    float cx = curve * t * t * len;                      // parabolic centerline bend
    float w  = halfwid * (1.0 - t) * (0.55 + 0.65*sin(t*3.14159));  // taper w/ belly
    w = max(w, 0.004);
    float th = thick * (1.0 - 0.35*t);
    float3 q = p - float3(cx, 0.0, 0.0);
    float2 e = float2(q.x / w, q.z / max(th,1e-4));
    float dxy = (length(e) - 1.0) * min(w, th);          // approx elliptical cross-section
    float dcap = max(p.y - len, -p.y);
    return max(dxy, dcap) * 0.85;                        // safety factor vs oversteps
}

// broad CUPPED tulip petal: base at y=0, tip at y=len. wide belly, curls in +x (droop) and cups in z.
float bb_petal(float3 p, float len, float halfwid, float thick, float droop, float cup)
{
    float y  = clamp(p.y, 0.0, len);
    float t  = y / max(len, 1e-4);
    float cx = droop * t * t * len;                      // droop bend
    float cz = cup * sin(t*3.14159) * len * 0.10;        // cup the sheet forward
    float w  = halfwid * pow(sin(clamp(t,0.0,1.0)*3.14159), 0.45); // rounded lobe, 0 at both ends
    w = max(w, 0.004);
    float th = thick;
    float3 q = p - float3(cx, 0.0, cz);
    float2 e = float2(q.x / w, q.z / max(th,1e-4));
    float dxy = (length(e) - 1.0) * min(w, th);
    float dcap = max(p.y - len, -p.y - 0.02);
    return max(dxy, dcap) * 0.85;
}

// protea / pinecone CONE: teardrop egg, base at y=0, pointed top at y=h. rBase widest near base.
float bb_cone(float3 p, float h, float rBase)
{
    float t = clamp(p.y / max(h,1e-4), 0.0, 1.0);
    float rad = rBase * pow(1.0 - t, 0.55) * (0.35 + 0.85*sin(t*3.14159*0.85 + 0.15));
    rad = max(rad, 0.003);
    float dr = length(p.xz) - rad;
    float dcap = max(p.y - h, -p.y);
    return max(dr, dcap) * 0.9;
}

// blended BERRY / hydrangea cluster: a few small spheres smin-blended into a lumpy ball.
float bb_berry(float3 p, float R, float seed)
{
    float d = sd_sphere(p, R*0.7);
    [unroll] for (int i = 0; i < 5; i++){
        float a = 6.2831*sd_hash11(seed + i*1.7);
        float b = 3.1416*sd_hash11(seed + i*2.3 + 0.5);
        float rr = R*(0.42 + 0.30*sd_hash11(seed+i*3.1));
        float3 o = float3(sin(b)*cos(a), cos(b), sin(b)*sin(a)) * R*0.55;
        d = op_smin(d, sd_sphere(p - o, rr), R*0.28);
    }
    return d;
}

// ---- surface-pattern helpers (albedo modulation; take local/world pos + normal) ----
// lengthwise stripe/vein value (0..1) for blades & petals, from an along-axis coordinate.
float bb_lines(float s, float freq, float sharp)
{
    float f = frac(s * freq);
    float m = min(f, 1.0 - f);
    return smoothstep(sharp, 0.0, m);
}
// reticulated hex-ish cell value (0=cell body, 1=dark seam) from a 2D coordinate.
float bb_reticulate(float2 g, out float cellRnd)
{
    g.x += 0.5 * floor(g.y);                             // brick offset -> hex feel
    float2 id = floor(g);
    float2 f  = frac(g) - 0.5;
    cellRnd = sd_hash21(id + 3.7);
    float cheb = max(abs(f.x), abs(f.y));
    float rad  = length(f);
    return smoothstep(0.30, 0.46, lerp(cheb, rad, 0.5));
}
// scattered dot value for berries (1 on dot).
float bb_dots(float2 g)
{
    float2 f = frac(g) - 0.5;
    return smoothstep(0.30, 0.16, length(f));
}

// ================= CANONICAL kinds (centered at origin, y in [-1,1], flat forms face +Z) =================
// Meant to be instanced from a part buffer (scale/rotate/place per record), like sdf_blob.hlsli.
// Requires sdf_extras.hlsli (sd_bezierTube) for wire/stamen.
#define BOT_BLADE  0
#define BOT_PETAL  1
#define BOT_CONE   2
#define BOT_BERRY  3
#define BOT_WIRE   4
#define BOT_STAMEN 5
#define BOT_COUNT  6
static const float BOT_BOUND_R = 1.35;   // renderers cull by this * instance max-axis

float bot_blade(float3 p)
{
    float t = (clamp(p.y,-1.0,1.0)+1.0)*0.5;                  // 0 base .. 1 tip
    float w = 0.17*(1.0-t)*(0.55+0.70*sin(t*3.14159)); w = max(w,0.006);
    float th = 0.055*(1.0-0.35*t);
    float2 e = float2(p.x/w, p.z/max(th,1e-4));
    float dxy = (length(e)-1.0)*min(w,th);
    float dcap = max(p.y-1.0, -p.y-1.0);
    return max(dxy,dcap)*0.85;
}
float bot_petal(float3 p)
{
    float t = (clamp(p.y,-1.0,1.0)+1.0)*0.5;
    float w = 0.52*pow(sin(t*3.14159),0.45); w = max(w,0.006);
    float th = 0.05;
    float cz = 0.16*sin(t*3.14159);                          // cup forward
    float3 q = p - float3(0,0,cz);
    float2 e = float2(q.x/w, q.z/max(th,1e-4));
    float dxy = (length(e)-1.0)*min(w,th);
    float dcap = max(p.y-1.0, -p.y-1.0);
    return max(dxy,dcap)*0.85;
}
float bot_cone(float3 p)
{
    float t = (clamp(p.y,-1.0,1.0)+1.0)*0.5;                  // 0 base .. 1 top
    float rad = 0.5*pow(1.0-t,0.55)*(0.35+0.85*sin(t*3.14159*0.85+0.15)); rad = max(rad,0.01);
    float dr = length(p.xz)-rad;
    float dcap = max(p.y-1.0, -p.y-1.0);
    return max(dr,dcap)*0.9;
}
float bot_wire(float3 p)
{
    return sd_bezierTube(p, float3(-0.9,-0.7,0.10), float3(0.35,0.4,0.55), float3(0.9,-0.25,0.05), 0.085);
}
float bot_stamen(float3 p)
{
    return sd_bezierTube(p, float3(0.0,-1.0,0.0), float3(-0.55,0.55,0.35), float3(0.25,1.0,0.10), 0.05);
}
float bot_obj_sdf(float3 p, int kind)
{
    if (kind == BOT_BLADE)  return bot_blade(p);
    if (kind == BOT_PETAL)  return bot_petal(p);
    if (kind == BOT_CONE)   return bot_cone(p);
    if (kind == BOT_BERRY)  return bb_berry(p, 0.9, 3.1);
    if (kind == BOT_WIRE)   return bot_wire(p);
    return bot_stamen(p);
}

// ---- toon palette + hue + per-kind flat albedo (with surface pattern) ----
static const float3 BOTP_LINE   = float3(0.05, 0.03, 0.12);
static const float3 BOTP_YELLOW = float3(1.00, 0.86, 0.08);
float3 bot_hue(float3 c, float a)
{
    float3 k = float3(0.57735,0.57735,0.57735);
    float ca=cos(a), sa=sin(a);
    return c*ca + cross(k,c)*sa + k*dot(k,c)*(1.0-ca);
}
// kind, per-instance tint (0..1), local hit point q, world normal n, global hue angle.
// isFlower: out flag so caller knows whether hue already applied (berry/wire excluded).
float3 bot_albedo(int kind, float tint, float3 q, float3 n, float hueA)
{
    float3 an = abs(n);
    float2 tp = (an.x > an.y && an.x > an.z) ? q.yz : ((an.y > an.z) ? q.xz : q.xy);
    float3 col; bool flower = true;
    if (kind == BOT_BLADE){
        col = lerp(lerp(float3(0.92,0.13,0.10), float3(0.97,0.46,0.08), tint),
                   float3(1.0,0.86,0.08), saturate(tint*tint*1.4-0.3));
        if (tint > 0.86) col = float3(0.5,0.78,0.22);
        float veins = bb_lines(tp.x, 5.5, 0.14);
        col = lerp(col, float3(1.0,0.9,0.15), veins*0.6);
    } else if (kind == BOT_PETAL){
        float3 pk[4] = { float3(0.98,0.55,0.66), float3(0.90,0.10,0.52),
                         float3(0.20,0.30,0.94), float3(1.0,0.82,0.10) };
        col = pk[(int)floor(saturate(tint)*3.99)];
        float hatch = bb_lines(tp.x, 7.0, 0.12);
        col = lerp(col, col*0.5, hatch*0.7);
    } else if (kind == BOT_CONE){
        col = lerp(float3(0.88,0.13,0.10), float3(1.0,0.82,0.14), tint);
        float rnd; float seam = bb_reticulate(tp*6.0, rnd);
        col = lerp(col*(0.72+0.55*rnd), float3(0.26,0.04,0.18), smoothstep(0.4,0.75,seam));
    } else if (kind == BOT_BERRY){
        col = lerp(float3(0.64,0.70,0.82), float3(0.36,0.42,0.58), bb_dots(tp*7.0));
        flower = false;
    } else if (kind == BOT_WIRE){
        col = BOTP_LINE; flower = false;
    } else {
        col = BOTP_YELLOW;
    }
    if (flower) col = bot_hue(col, hueA);
    return col;
}

#endif // SDF_BOTANY_HLSLI
