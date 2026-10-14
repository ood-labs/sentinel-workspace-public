// lens_common.hlsli -- shared by BR_Lens's passes.
//
// CONTRACT: a pass that includes this binds data:0 (BR_Trip's records) and data:1 (BR_Render's
// scene records -- the camera this frame was rendered with comes from there).
#ifndef BR_LENS_COMMON_HLSLI
#define BR_LENS_COMMON_HLSLI

#include "../_shared/br_records.hlsli"
#include "../_shared/br_shade.hlsli"
#define TRIP_REC(i) lensTripRec(i)
BRRec lensTripRec(int i)
{
    BRRec r;
    if (_Data0_Count >= 13u) { r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; }
    else { r.head = 0; r.dims = 0; r.look = 0; r.meta = 0; }
    return r;
}
#include "../_shared/br_trip.hlsli"
#include "../_shared/br_light_defs.hlsli"
#include "../_shared/br_camtexels.hlsli"

// BR_Render scene buffer: the view-projection of its latest frame (rows 15..18) -- the fallback
// when an image's own camera header cannot be read
#define LENS_SC_VP_CUR 15
float4x4 lensViewProj()
{
    if (_Data1_Count < 19u) return float4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
    return float4x4(_Data1[LENS_SC_VP_CUR].dims, _Data1[LENS_SC_VP_CUR + 1].dims, _Data1[LENS_SC_VP_CUR + 2].dims, _Data1[LENS_SC_VP_CUR + 3].dims);
}
// world point -> uv (0..1, y down) and view depth; false behind the camera
bool lensProject(float4x4 vp, float3 x, out float2 uv, out float w)
{
    float4 c = mul(vp, float4(x, 1.0));
    w = c.w;
    uv = float2(c.x / max(c.w, 1e-4) * 0.5 + 0.5, 0.5 - c.y / max(c.w, 1e-4) * 0.5);
    return c.w > 0.05;
}

// THE VISUAL FIELD: drug visuals are distortions of what you see, not of the room, so on top of
// the surface effects the renderer draws, the whole image breathes and drifts here: a slow
// screen-space swim everywhere, and around every anchor (projected to where it appears) a pulse
// that swells and recedes, a twist, a sag, a stream. Returns the displacement in UV.
float2 lensWarp(float2 uv, float aspect, BRTrip T, float4x4 vp, float amount)
{
    float2 d = 0;
    if (T.dose <= 0.0 || amount <= 0.0) return d;
    float t = T.time;
    // overdrive: every displacement larger and its texture finer
    float AMP = tripAmp(T), F = tripFreq(T);
    // everywhere: a slow drift, a few pixels, its eddies sized by the trip's swim scale
    float2 q = float2(uv.x * aspect, uv.y) * 2.4 * F / max(T.scale, 0.1);
    float2 n = float2(brVN3(float3(q, t * 0.06)), brVN3(float3(q + 7.3, t * 0.07)));
    d += n * 0.0030 * T.drift * T.dose * AMP;
    // the whole field breathes very slightly about the centre
    d += (uv - 0.5) * 0.0045 * T.breathe * T.dose * AMP * sin(t * 0.7);
    // pushed past a full dose, the field ripples in rings round the centre as well
    if (T.push > 0.0)
    {
        float2 rc = (uv - 0.5) * float2(aspect, 1.0);
        float rl = length(rc);
        d += (rc / max(rl, 1e-4)) / float2(aspect, 1.0) * sin(rl * 26.0 * F - t * 1.7) * 0.0022 * T.push * T.drift;
    }
    [loop] for (int i = 0; i < T.anchors; i++)
    {
        BRAnchor A = tripAnchor(i);
        float2 c; float w;
        if (A.on && lensProject(vp, A.c, c, w))
        {
            // the anchor's reach on screen: its radius over its distance, through the lens
            float rs = clamp(A.radius / w * 0.85, 0.03, 0.6);
            float2 dv = (uv - c) * float2(aspect, 1.0);
            float f = exp(-dot(dv, dv) / (rs * rs));
            float s = A.strength * T.dose * f * AMP;
            float ph = tripPulse(A, t);
            if (A.kind == TK_BREATHE || A.kind == TK_BLOOM)
                d -= (uv - c) * s * ((A.kind == TK_BREATHE) ? 0.035 : 0.018) * ph;
            else if (A.kind == TK_SWIRL)
            {
                float ang = s * 0.10 * ph;
                float2 r0 = uv - c;
                d += float2(r0.x * cos(ang) - r0.y * sin(ang), r0.x * sin(ang) + r0.y * cos(ang)) - r0;
            }
            else if (A.kind == TK_MELT)
                d.y -= s * 0.010 * (0.6 + 0.4 * ph) * (0.6 + 0.4 * brVN3(float3(uv.x * 30.0 * F, 0.0, t * 0.1)));
            else
                d.x += s * 0.008 * sin(t * A.rate * 6.2831853 + uv.y * 9.0 * F + A.phase);
        }
    }
    return d * amount;
}

// ---- LAMP RAINBOWS ----------------------------------------------------------------------------
// The lamps hold still in the room (BR_Render gives them no warp): their trip happens in the eye.
// Off every lit lamp the dose draws soft bands of iridescence that flow outward from the lamp's
// OWN OUTLINE: the shade's silhouette (its lower and upper rim, projected; a globe's circle), and
// each band an offset of it, so near the lamp they hug a drum shade's trapezoid or a dome's curve
// and grow rounder as they leave, the way light spreads. They are as strong as the lamp is seen
// (the image's own ray distances at the bulb, against the bulb's). The trip's geometry turns a
// six-fold flower slowly through them. OVERDRIVE (T.push) packs the bands closer, spreads them
// across the room and turns the flower harder.
// Records: BR_Render's scene buffer, COUNTS.dims.y lamps from LAMP0, head (role, kind, obj,
// variant), dims (bulb xyz, power).
#define LENS_SC_COUNTS 19
#define LENS_SC_LAMP0  20
float3 lensSpectrum(float h)
{
    float3 c = saturate(abs(frac(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0);
    return c * c * (3.0 - 2.0 * c);
}
// the luminous outline of a lamp around its bulb: (lower rim height, its radius, upper rim
// height, its radius) in metres from the bulb, from BR_Render's lamp models (br_furniture.hlsli)
float4 lensShadeProfile(int kind, int v)
{
    if (kind == 6)                                   // floor lamps: arc dome, drum, slim drum
    {
        if (v == 0) return float4(-0.05, 0.19, 0.07, 0.12);
        if (v == 1) return float4(-0.12, 0.25, 0.20, 0.22);
        return float4(-0.12, 0.21, 0.20, 0.18);
    }
    if (kind == 7)                                   // table lamps: drum shades
        return (v == 0) ? float4(-0.11, 0.19, 0.15, 0.155) : float4(-0.11, 0.16, 0.11, 0.095);
    if (v == 0) return float4(0.0, 0.20, 0.0, 0.20); // pendants: globe, lantern, dome
    if (v == 1) return float4(-0.02, 0.25, 0.02, 0.25);
    return float4(-0.06, 0.23, 0.08, 0.12);
}
// 2D distance to the hull of a circle r1 at the origin and a circle r2 at (0, h)
float lensUnevenCapsule(float2 p, float r1, float r2, float h)
{
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(max(1.0 - b * b, 1e-4));
    float k = dot(p, float2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}
float3 lensLampRainbows(float2 uv, float aspect, BRTrip T, CamHdr fc, Texture2D<float4> img, float2 res, float amount)
{
    float3 acc = 0;
    if (T.dose <= 0.0 || amount <= 0.0 || _Data1_Count < 32u || !fc.ok) return acc;
    int n = clamp((int)round(_Data1[LENS_SC_COUNTS].dims.y), 0, 12);
    float t = T.time;
    float F = tripFreq(T);
    int2 mx = int2(res) - 1;
    float2 asp = float2(aspect, 1.0);
    float2 pu = uv * asp;
    [loop] for (int i = 0; i < n; i++)
    {
        float4 hd = _Data1[LENS_SC_LAMP0 + i].head, dm = _Data1[LENS_SC_LAMP0 + i].dims;
        float4 prof = lensShadeProfile((int)round(hd.y), (int)round(hd.w));
        float2 c, cb, ct, cp;
        float w0, wb, wt, wp;
        float3 toB = dm.xyz - fc.eye;
        float tb = length(toB);
        float3 perp = cross(toB / max(tb, 1e-4), float3(0, 1, 0));
        perp = (dot(perp, perp) > 1e-6) ? normalize(perp) : float3(1, 0, 0);
        // (lensProject, not camProject: a lamp at the top of the picture projects its offset
        // points off screen, and camProject refuses those)
        if (abs(hd.x - ROLE_LAMP) < 0.5 && (int)round(hd.y) != LAMP_KIND_FIRE && dm.w > 1e-4
            && lensProject(fc.vp, dm.xyz, c, w0) && lensProject(fc.vp, dm.xyz + perp * 0.25, cp, wp)
            && lensProject(fc.vp, dm.xyz + float3(0, prof.x, 0), cb, wb) && lensProject(fc.vp, dm.xyz + float3(0, prof.z, 0), ct, wt))
        {
            // screen heights per metre at the lamp, and the outline in screen heights
            float ppm = length((cp - c) * asp) / 0.25;
            float rb = prof.y * ppm, rt = prof.w * ppm;
            float2 pb = cb * asp, pt = ct * asp;
            float2 ax = pt - pb;
            float h = length(ax);
            float d;
            if (h <= abs(rb - rt) + 1e-5) d = min(length(pu - pb) - rb, length(pu - pt) - rt);
            else
            {
                float2 ey = ax / h, ex = float2(ey.y, -ey.x);
                float2 q = pu - pb;
                d = lensUnevenCapsule(float2(dot(q, ex), dot(q, ey)), rb, rt, h);
            }
            float R = max(rb, rt);
            // how much of it is seen: the image's ray distance round the bulb against the bulb's
            float vis = 0.0;
            [unroll] for (int k = 0; k < 5; k++)
            {
                float2 o = (k == 1) ? float2(1, 0) : (k == 2) ? float2(-1, 0) : (k == 3) ? float2(0, 1) : (k == 4) ? float2(0, -1) : float2(0, 0);
                int2 px = clamp(int2((c + o * R * 0.5 / asp) * res), int2(0, 4), mx);
                float ts = abs(img.Load(int3(px, 0)).a);
                vis += saturate((ts - (tb - 0.45)) / 0.15);
            }
            // a lamp off the edge of the picture fades out (its taps would read the border)
            float edge = min(min(c.x, c.y), 1.0 - max(c.x, c.y));
            vis *= 0.2 * smoothstep(-0.12, 0.04, edge);
            float sd = (float)i * 1.618;
            // close round the lamp at a normal dose, a little further for a lamp that looks big;
            // overdrive spreads them across the room
            float reach = clamp(R * 1.6, 0.025, 0.09) * (1.0 + 1.4 * T.push);
            float env = smoothstep(-0.003, 0.012, d) * exp(-max(d, 0.0) / reach);
            // soft bands that flow outward, each a whole rainbow -- red on its inner edge to violet
            // on its outer -- with a soft dark gap before the next (a band peaking at one hue
            // read as alternating magenta and green rings)
            float ph = d * F / (0.045 + 0.4 * R) - t * 0.22 + sd;
            float u = frac(ph);
            float band = smoothstep(0.0, 0.22, u) * smoothstep(0.98, 0.62, u);
            float3 col = lensSpectrum(u * 0.80);
            // the geometry's six-fold flower, turning through the bands
            float2 dv = pu - c * asp;
            float ang = (dot(dv, dv) > 1e-12) ? atan2(dv.y, dv.x) : 0.0;
            float petal = 0.5 + 0.5 * cos(ang * 6.0 + ph * 1.3 - t * 0.35 + sd);
            float flower = T.geometry * (0.30 + 0.25 * saturate(T.push));
            // a distant lamp wears its bands a little fainter
            float size = 0.5 + 0.5 * saturate(R / 0.05);
            acc += col * band * (1.0 - flower + flower * petal) * env * vis * dm.w * size * 0.30;
        }
    }
    return acc * amount * T.dose * (1.0 + 0.6 * T.push);
}

// filmic view: a max-channel shoulder for saturated mid-tones, per-channel compression for the
// brightest highlights (they burn through yellow to white instead of going pink)
float3 lensFilmic(float3 c)
{
    float l = max(c.r, max(c.g, c.b));
    float3 mc = c * ((1.0 - exp(-l * 1.35)) / max(l, 1e-5));
    float3 pc = 1.0 - exp(-max(c, 0.0) * 1.35);
    return lerp(mc, pc, smoothstep(0.6, 3.0, l) * 0.85);
}

// Saturation around luminance, in linear light (HSV saturation on linear values is already near 1
// for warm light, so scaling it crushed the blue channel of every lamp-lit wall).
float3 lensSaturate(float3 c, float k)
{
    float l = dot(c, float3(0.2126, 0.7152, 0.0722));
    return max(l + (c - l) * k, 0.0);
}
// Hue rotation about the grey axis (Rodrigues), luminance-neutral enough for small angles.
float3 lensHueRotate(float3 c, float a)
{
    const float3 k = float3(0.57735, 0.57735, 0.57735);
    float ca = cos(a), sa = sin(a);
    return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

#endif
