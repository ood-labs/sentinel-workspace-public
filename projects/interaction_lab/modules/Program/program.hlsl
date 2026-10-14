// Program - the Score's show, rendered. The hall (score.hlsli) as one distance field, through the
// injected internal camera (which the Score drives by expression), in the light of the act showing,
// composited with the cards and the hand-off the Score resolves at the playhead (R0, R5):
//
//   cut     the act showing, alone
//   dip     the leaving act fades to black over the first half, the next rises out of it over the
//           second; the camera and the light change in the dark
//   glide   between rails: one picture - the camera blends (the Score) and so does the light (here);
//           with a card on either side: a dissolve in linear light
//
// A card is drawn exactly as the Score's stage draws it (score.hlsli: the item records, the palette,
// the word's em per cap height), so what the editor shows is what leaves. While only a card shows,
// nothing is marched.
//
// The march compiles each costly piece once: the field is evaluated in four places (the march, the
// normal, occlusion and the shadow), each inside a loop - the primary ray and its one traced
// reflection share a loop, the sun and the nearest lamp share the shadow, four rays share the pixel.
#define IL_TYPE_TEX _Tex1
#include "_labels.generated.hlsli"                 // before il_text: it turns on the label functions
#include "../_shared/ui/il_text.hlsli"

StructuredBuffer<float4> SB : register(t0);         // the Score (data input)
#define SC_BUF SB
#include "../_shared/score.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float3 lin(float3 c)  { return pow(saturate(c), 2.2); }
float3 disp(float3 c) { return pow(saturate(c), 1.0 / 2.2); }

// ---------------------------------------------------------------- the hall as a distance field
#define M_FLOOR  0.0
#define M_WALL   1.0
#define M_COLUMN 2.0
#define M_PLINTH 3.0
#define M_SPHERE 4.0
#define M_RING   5.0
#define M_STACK  6.0
#define M_GROUND 7.0                                // outside the hall

float sdBox(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
// an upright cylinder from y0 to y1
float sdCylY(float3 p, float r, float y0, float y1)
{
    float2 d = float2(length(p.xz) - r, abs(p.y - 0.5 * (y0 + y1)) - 0.5 * (y1 - y0));
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
// the editors' turn (Score: plan, view): world = centre + rot2(local, t)
float2 rot2(float2 v, float t) { float c = cos(t), s = sin(t); return float2(v.x * c + v.y * s, -v.x * s + v.y * c); }
void pick(inout float2 r, float d, float m) { if (d < r.x) r = float2(d, m); }

// (distance, material). Shadow rays leave out the floor: it can never shade a ray climbing toward a
// light, and a ray toward a low sun would otherwise crawl along it and run out of steps.
float2 hall(float3 p, bool floorToo)
{
    bool inside = p.z >= 0.0 && p.z <= SC_HALL_L && abs(p.x) <= SC_HALL_W;
    float2 r = float2(floorToo ? p.y : 1e3, inside ? M_FLOOR : M_GROUND);
    float3 a = float3(abs(p.x), p.y, p.z);          // the hall is mirrored about x = 0
    pick(r, sdBox(a - float3(SC_HALL_W + 0.5 * SC_WALL_T, 0.5 * SC_WALL_H, 0.5 * SC_HALL_L), float3(0.5 * SC_WALL_T, 0.5 * SC_WALL_H, 0.5 * SC_HALL_L)), M_WALL);
    pick(r, sdBox(p - float3(0.0, 0.5 * SC_WALL_H, SC_HALL_L + 0.5 * SC_WALL_T), float3(SC_HALL_W + SC_WALL_T, 0.5 * SC_WALL_H, 0.5 * SC_WALL_T)), M_WALL);
    // the columns: the nearest in each (mirrored) row - a shaft, a base, an abacus
    float k = clamp(round((p.z - SC_COL_Z0) / SC_COL_DZ), 0.0, (float)(SC_COL_N - 1u));
    float3 q = float3(a.x - SC_COL_X, p.y, p.z - (SC_COL_Z0 + SC_COL_DZ * k));
    float col = sdCylY(q, SC_COL_R, 0.0, SC_COL_H);
    col = min(col, sdCylY(q, SC_COL_R + 0.09, 0.0, 0.24));
    col = min(col, sdBox(q - float3(0.0, SC_COL_H + 0.09, 0.0), float3(0.44, 0.09, 0.44)));
    pick(r, col, M_COLUMN);
    // the plinths: the nearest
    float w = clamp(round((p.z - scWorkZ(0u)) / 10.0), 0.0, 2.0);
    pick(r, sdBox(p - float3(0.0, 0.5 * SC_PLINTH_H, scWorkZ(0u) + 10.0 * w), float3(SC_PLINTH_HW, 0.5 * SC_PLINTH_H, SC_PLINTH_HW)), M_PLINTH);
    // the works: the sphere, the standing ring (its axis along x), the stack of turned blocks
    pick(r, length(p - float3(0.0, SC_PLINTH_H + SC_SPHERE_R, scWorkZ(0u))) - SC_SPHERE_R, M_SPHERE);
    float3 g = p - float3(0.0, SC_PLINTH_H + SC_RING_R + SC_RING_T, scWorkZ(1u));
    pick(r, length(float2(length(g.yz) - SC_RING_R, g.x)) - SC_RING_T, M_RING);
    float st = 1e3;
    [unroll] for (uint b = 0u; b < 3u; b++)
    {
        float4 bl = scBlock(b);
        float3 o = p - float3(0.0, bl.y, scWorkZ(2u));
        o.xz = rot2(o.xz, -bl.z);
        st = min(st, sdBox(o, bl.xxx - 0.015) - 0.015);
    }
    pick(r, st, M_STACK);
    return r;
}

// nothing stands above the walls: a ray climbing past them has left the hall
#define TOP 6.3

bool march(float3 ro, float3 rd, uint steps, float tmax, out float t, out float m)
{
    t = 0.02;
    m = -1.0;
    bool hit = false;
    [loop] for (uint i = 0u; i < steps; i++)
    {
        float3 p = ro + rd * t;
        if (t > tmax || (p.y > TOP && rd.y >= 0.0)) break;
        float2 h = hall(p, true);
        if (h.x < 0.0006 * t + 0.0004) { hit = true; m = h.y; break; }
        t += h.x * 0.92;
    }
    return hit;
}

float3 normalAt(float3 p)
{
    float3 n = 0.0;
    [loop] for (uint i = 0u; i < 4u; i++)               // the tetrahedron, one field call compiled
    {
        float3 e = float3((i == 0u || i == 3u) ? 1.0 : -1.0, (i >= 2u) ? 1.0 : -1.0, (i == 1u || i == 3u) ? 1.0 : -1.0);
        n += e * hall(p + e * 0.0007, true).x;
    }
    return normalize(n);
}

float occlusion(float3 p, float3 n, uint taps)
{
    float occ = 0.0, sca = 1.0;
    [loop] for (uint i = 0u; i < 8u; i++)                // a constant bound (FXC proves it ends)
    {
        if (i >= taps) break;
        float h = 0.03 + 0.22 * (float)i / max((float)taps - 1.0, 1.0);
        occ += (h - hall(p + n * h, true).x) * sca;
        sca *= 0.82;
    }
    return saturate(1.0 - 1.6 * occ);
}

// The improved soft shadow (the penumbra estimated from consecutive steps, so it bands less),
// started a per-pixel distance along the ray so what banding remains turns to grain.
float softShadow(float3 ro, float3 rd, uint steps, float tmax, float k, float jitter)
{
    float res = 1.0, t = 0.02 + 0.06 * jitter, ph = 1e10;
    [loop] for (uint i = 0u; i < 64u; i++)
    {
        if (i >= steps) break;
        float3 p = ro + rd * t;
        if (t > tmax || (p.y > TOP && rd.y >= 0.0)) break;
        float h = hall(p, false).x;
        float y = h * h / (2.0 * ph);
        float d = sqrt(max(h * h - y * y, 0.0));
        res = min(res, k * d / max(t - y, 1e-4));
        ph = h;
        if (res < 0.003) break;
        t += clamp(h, 0.02, 1.2);
    }
    return smoothstep(0.0, 1.0, saturate(res));
}
// interleaved gradient noise: a cheap per-pixel offset
float ign(float2 p) { return frac(52.9829189 * frac(dot(p, float2(0.06711056, 0.00583715)))); }

// ---------------------------------------------------------------- light: day, dusk, night
struct Mood { float3 sun; float3 sunCol; float3 skyTop; float3 skyHor; float3 amb; float lamps; float fog; };

Mood moodOf(uint li)
{
    Mood m;
    if (li == SC_DAY)
    {
        m.sun = normalize(float3(-0.45, 0.82, 0.35));          // high, from behind the left wall
        m.sunCol = float3(1.00, 0.93, 0.82) * 2.0;
        m.skyTop = float3(0.15, 0.30, 0.60);
        m.skyHor = float3(0.60, 0.68, 0.78);
        m.amb = float3(0.40, 0.46, 0.56) * 0.48;
        m.lamps = 0.0;
        m.fog = 0.004;
    }
    else if (li == SC_DUSK)
    {
        m.sun = normalize(float3(0.15, 0.18, -0.97));          // low, in through the open end: the columns
                                                               // lay long shadows down the hall
        m.sunCol = float3(1.00, 0.46, 0.18) * 2.4;
        m.skyTop = float3(0.06, 0.06, 0.19);
        m.skyHor = float3(0.90, 0.40, 0.24);
        m.amb = float3(0.34, 0.21, 0.30) * 0.42;
        m.lamps = 0.3;
        m.fog = 0.010;
    }
    else
    {
        m.sun = normalize(float3(0.35, 0.62, -0.45));          // the moon
        m.sunCol = float3(0.42, 0.52, 0.85) * 0.22;
        m.skyTop = float3(0.004, 0.006, 0.016);
        m.skyHor = float3(0.020, 0.025, 0.045);
        m.amb = float3(0.05, 0.06, 0.09) * 0.55;
        m.lamps = 1.0;
        m.fog = 0.006;
    }
    return m;
}
Mood mixMood(Mood a, Mood b, float w)
{
    Mood m;
    m.sun = normalize(lerp(a.sun, b.sun, w));
    m.sunCol = lerp(a.sunCol, b.sunCol, w);
    m.skyTop = lerp(a.skyTop, b.skyTop, w);
    m.skyHor = lerp(a.skyHor, b.skyHor, w);
    m.amb = lerp(a.amb, b.amb, w);
    m.lamps = lerp(a.lamps, b.lamps, w);
    m.fog = lerp(a.fog, b.fog, w);
    return m;
}

// the lamps over the works (night; coming on at dusk): spots pointing straight down, each throwing a
// pool round its work and leaving the hall between them dark
float3 lampPos(uint i) { return float3(0.0, 4.6, scWorkZ(i)); }
#define LAMP_COL float3(1.00, 0.70, 0.40)
#define LAMP_I   30.0
float lampCone(float3 l) { return smoothstep(0.80, 0.93, -l.y); }      // l: surface to lamp; 22-37 degrees

float3 sky(float3 rd, Mood md, bool stars)
{
    float h = saturate(rd.y * 1.4 + 0.06);
    float3 c = lerp(md.skyHor, md.skyTop, sqrt(h));
    float sd = max(dot(rd, md.sun), 0.0);
    c += md.sunCol * (pow(sd, 900.0) * 6.0 + pow(sd, 10.0) * 0.05);    // the disc and its glow
    // stars, where the sky is dark enough to hold them
    float2 sp = rd.xz / max(rd.y, 0.04);
    float star = step(0.9975, ilHash21(floor(sp * 90.0))) * saturate(rd.y * 4.0);
    c += stars ? star * 0.6 * saturate(1.0 - dot(md.skyTop, float3(1.0, 1.0, 1.0)) * 25.0) : 0.0;
    return c;
}

// ---------------------------------------------------------------- materials and shading
struct Mat { float3 albedo; float rough; float3 f0; float metal; };

Mat materialAt(float m, float3 p, float t)
{
    Mat r;
    r.albedo = float3(0.5, 0.5, 0.5);
    r.rough = 0.7;
    r.f0 = 0.04;
    r.metal = 0.0;
    if (m == M_FLOOR)
    {
        // honed travertine, a slab every 2 m across and 4 m along: the joints the Score's plan grid
        // and its view's outline draw
        float2 cell = float2(round(p.x * 0.5), round(p.z * 0.25));
        float dj = min(abs(p.x - 2.0 * cell.x), abs(p.z - 4.0 * cell.y));
        float joint = (1.0 - smoothstep(0.006, 0.018 + 0.0015 * t, dj)) * saturate(1.3 - t / 45.0);
        float tone = 0.92 + 0.08 * ilHash21(cell + 17.0);
        r.albedo = float3(0.44, 0.40, 0.35) * tone * (1.0 - 0.6 * joint);
        r.rough = 0.28;
        r.f0 = 0.035;
    }
    else if (m == M_GROUND)
    {
        r.albedo = float3(0.20, 0.19, 0.17) * (0.94 + 0.06 * ilHash21(floor(p.xz * 14.0)));   // fine gravel
        r.rough = 0.95;
    }
    else if (m == M_WALL)   { r.albedo = float3(0.50, 0.45, 0.39); r.rough = 0.9; }
    else if (m == M_COLUMN) { r.albedo = float3(0.62, 0.59, 0.54); r.rough = 0.6; }
    else if (m == M_PLINTH) { r.albedo = float3(0.085, 0.085, 0.09); r.rough = 0.45; }
    else if (m == M_SPHERE) { r.albedo = float3(0.70, 0.22, 0.07); r.rough = 0.16; r.f0 = 0.05; }     // glazed terracotta
    else if (m == M_RING)   { r.albedo = float3(0.62, 0.63, 0.65); r.rough = 0.10; r.metal = 1.0; r.f0 = float3(0.62, 0.63, 0.65); }
    else if (m == M_STACK)  { r.albedo = float3(0.20, 0.17, 0.14); r.rough = 0.75; }                   // oiled oak
    return r;
}

// how much of the scene a surface reflects toward the eye (Schlick), and its colour
float3 reflectance(Mat mt, float3 n, float3 v)
{
    float f = pow(1.0 - saturate(dot(n, v)), 5.0);
    float gloss = 1.0 - mt.rough;
    return (mt.f0 + (1.0 - mt.f0) * f) * gloss * gloss;
}

// direct light and sky light at a hit; shadows and occlusion when given steps (the primary ray)
float3 shadeHit(float3 p, float3 n, float3 rd, Mat mt, Mood md, uint shadowSteps, uint aoTaps, float jitter)
{
    float3 v = -rd;
    float3 pp = p + n * 0.005;
    float occ = 1.0;
    if (aoTaps > 0u) occ = occlusion(p, n, aoTaps);       // (a ?: would run the loop either way)
    float3 diff = mt.albedo * (1.0 - mt.metal);
    float3 spc = lerp(float3(0.04, 0.04, 0.04), mt.f0, mt.metal);
    float shin = 2.0 / max(mt.rough * mt.rough, 0.002);
    float3 col = 0.0;
    // the key lights: the sun (or moon), then the nearest lamp - one shadow call between them
    uint near = (uint)clamp(round((p.z - scWorkZ(0u)) / 10.0), 0.0, 2.0);
    [loop] for (uint L = 0u; L < 2u; L++)
    {
        float3 ldir;
        float3 lcol;
        float tmax;
        if (L == 0u) { ldir = md.sun; lcol = md.sunCol; tmax = 70.0; }
        else
        {
            float3 dl = lampPos(near) - p;
            float d2 = dot(dl, dl);
            ldir = dl * rsqrt(d2);
            lcol = LAMP_COL * LAMP_I * md.lamps * lampCone(-ldir) / (d2 + 0.3);
            tmax = sqrt(d2);
        }
        float ndl = dot(n, ldir);
        if (ndl <= 0.0 || dot(lcol, float3(1.0, 1.0, 1.0)) < 1e-4) continue;
        float sh = 1.0;
        if (shadowSteps > 0u) sh = softShadow(pp, ldir, shadowSteps, tmax, 12.0, jitter);
        float3 hv = normalize(ldir + v);
        float sp = pow(max(dot(n, hv), 0.0), shin) * (shin + 8.0) / 25.0;
        col += (diff + spc * sp) * lcol * ndl * sh;
    }
    // the other two lamps, unshadowed
    [loop] for (uint i = 0u; i < 3u; i++)
    {
        if (i == near || md.lamps <= 0.0) continue;
        float3 dl = lampPos(i) - p;
        float d2 = dot(dl, dl);
        float3 l = dl * rsqrt(d2);
        col += diff * LAMP_COL * LAMP_I * md.lamps * lampCone(-l) / (d2 + 0.3) * max(dot(n, l), 0.0);
    }
    // the sky, and a little light thrown back up off the floor
    col += diff * md.amb * (0.55 + 0.45 * n.y) * occ;
    col += diff * md.sunCol * 0.035 * saturate(-n.y * 0.5 + 0.5) * saturate(md.sun.y * 2.0) * occ;
    return col;
}

void fog(inout float3 col, float t, Mood md)
{
    col = lerp(col, md.skyHor * 0.85, 1.0 - exp(-md.fog * t));
}

// One camera ray through the hall: the primary hit, then (reflectSteps > 0) one traced reflection
// off whatever reflects; with no trace, reflective surfaces see the sky.
float3 traceRay(float2 uv, Mood md, uint marchSteps, uint shadowSteps, uint aoTaps, uint reflectSteps, float jitter)
{
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nw = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 fw = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nw /= nw.w;
    fw /= fw.w;
    float3 ro = _CameraPos;
    float3 rd = normalize(fw.xyz - nw.xyz);
    float tmax = min(_CameraFar, 120.0);
    float3 acc = 0.0, thr = 1.0;
    uint bounces = (reflectSteps > 0u) ? 2u : 1u;        // a runtime count: FXC cannot peel the loop
    [loop] for (uint bounce = 0u; bounce < bounces; bounce++)
    {
        float t, m;
        bool hit = march(ro, rd, (bounce == 0u) ? marchSteps : reflectSteps, tmax, t, m);
        if (!hit) { acc += thr * sky(rd, md, bounce == 0u); break; }
        float3 p = ro + rd * t;
        float3 n = normalAt(p);
        Mat mt = materialAt(m, p, t);
        float3 kr = reflectance(mt, n, -rd);
        float3 c = shadeHit(p, n, rd, mt, md, (bounce == 0u) ? shadowSteps : 0u, (bounce == 0u) ? aoTaps : 0u, jitter);
        c *= 1.0 - kr * (1.0 - mt.metal);
        fog(c, t, md);
        acc += thr * c;
        float3 rf = reflect(rd, n);
        if (bounce == 0u && reflectSteps > 0u && mt.rough < 0.2 && max(kr.x, max(kr.y, kr.z)) > 0.02)
        {
            thr *= kr;
            ro = p + n * 0.01;
            rd = rf;
        }
        else
        {
            // untraced: the sky above, the lit floor below, blended across the horizon (no seam)
            float3 below = float3(0.44, 0.40, 0.35) * (md.amb + md.sunCol * saturate(md.sun.y) * 0.3 + LAMP_COL * md.lamps * 0.25);
            float3 env = lerp(below, sky(rf, md, false), smoothstep(-0.12, 0.12, rf.y));
            acc += thr * kr * env;
            break;
        }
    }
    return acc;
}

float3 acesFit(float3 x) { return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14)); }

// ---------------------------------------------------------------- the cards (as the Score's stage)
float3 card(uint a, float2 px, float2 res)
{
    float h = res.y;
    float2 c = 0.5 * res;
    uint li = scLight(a);
    float3 col = lin(scCardGround(li));
    [loop] for (uint j = 0u; j < SC_ITEMS; j++)           // the bar, the disc, then the word on top
    {
        uint k = SC_ITEMS - 1u - j;
        float4 it = scItem(a, k);
        if (it.w < 0.5) continue;
        float2 p = float2(c.x + it.x * h, c.y - it.y * h);
        float cov;
        float3 ink = lin(scCardInk(li));
        if (k == 2u)
        {
            float2 d = abs(px - p) - float2(it.z * h, SC_BAR_HT * h);
            cov = saturate(0.5 - max(d.x, d.y));
        }
        else if (k == 1u)
        {
            cov = saturate(it.z * h - length(px - p) + 0.5);
            ink = lin(scCardDisc(li));
        }
        else cov = ilLabel(px, p.x, p.y, it.z * h * SC_EM_PER_CAP, LB_W_0 + scWord(a), IL_CENTER);
        col = lerp(col, ink, cov);
    }
    return col;
}

// ---------------------------------------------------------------- the pixel
// Four rays: a rotated grid, averaged in (filmic) linear light.
static const float2 RGSS[4] = { float2(0.125, 0.375), float2(0.375, -0.125), float2(-0.125, -0.375), float2(-0.375, 0.125) };

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (id.x >= W || id.y >= H) return;
    float2 res = float2(W, H);
    float2 px = float2(id.xy) + 0.5;

    // what the Score resolved at the playhead (with no Score: the hall by day, no cards)
    bool valid = SB[SC_PM].x == SC_MAGIC && scActs() >= 1u;
    uint A = valid ? min(scShowA(), scActs() - 1u) : 0u;
    uint B = valid ? min(scShowB(), scActs() - 1u) : 0u;
    float u = valid ? saturate(scShowMix()) : 0.0;
    uint hk = valid ? scShowHand() : SC_CUT;
    bool railA = !valid || scKind(A) == SC_RAIL;
    bool railB = !valid || scKind(B) == SC_RAIL;
    bool handing = u > 0.0;

    // the picture's light: B's share is the glide's blend, or all of it past a dip's darkest point;
    // a card has no light of its own, so with one on either side the rail's light holds
    float w = (hk == SC_GLIDE) ? smoothstep(0.0, 1.0, u) : ((u >= 0.5) ? 1.0 : 0.0);
    w = !railA ? 1.0 : (!railB ? 0.0 : w);
    Mood md = mixMood(moodOf(valid ? scLight(A) : SC_DAY), moodOf(valid ? scLight(B) : SC_DAY), w);

    // the hall, when anything showing needs it
    float3 hall3 = 0.0;
    if (railA || (handing && railB))
    {
        uint ms = (uint)clamp(march_steps, 32, 256);
        uint ss = (uint)clamp(shadow_steps, 0, 64);
        uint ao = (uint)clamp(ao_taps, 0, 8);
        uint rs = (uint)clamp(reflect_steps, 0, 96);
        uint n = (rays == 1) ? 4u : 1u;
        [loop] for (uint i = 0u; i < n; i++)
        {
            float2 o = (n == 4u) ? RGSS[i] : float2(0.0, 0.0);
            hall3 += acesFit(traceRay((px + o) / res, md, ms, ss, ao, rs, frac(ign(px) + 0.618 * (float)i)) * exposure);
        }
        hall3 /= (float)n;
    }

    // the pictures either side of the hand-off, and the hand-off itself
    float3 picA = railA ? hall3 : card(A, px, res);
    float3 col = picA;
    if (handing)
    {
        float3 picB = railB ? hall3 : ((B == A) ? picA : card(B, px, res));
        if (hk == SC_DIP) col = (u < 0.5) ? picA * (1.0 - 2.0 * u) : picB * (2.0 * u - 1.0);
        else if (hk == SC_GLIDE) col = (railA && railB) ? hall3 : lerp(picA, picB, smoothstep(0.0, 1.0, u));
    }

    if (!valid)
    {
        float w0 = ilLabelW(LB_NOSCORE, 13.0);
        float2 d = abs(px - float2(16.0 + 0.5 * w0, res.y - 18.0)) - float2(0.5 * w0 + 10.0, 12.0);
        col = lerp(col, float3(0.01, 0.01, 0.012), 0.8 * saturate(0.5 - max(d.x, d.y)));
        col = lerp(col, float3(0.80, 0.80, 0.78), ilLabel(px, 16.0, res.y - 18.0, 13.0, LB_NOSCORE, IL_LEFT));
    }
    OutputUAV[id.xy] = float4(disp(col), 1.0);
}
