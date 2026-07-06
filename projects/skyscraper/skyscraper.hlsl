// skyscraper.hlsl — single-module generative skyscraper (raymarched SDF).
// Seed-driven setback massing + window-cut facade lattice (piers, spandrels,
// mechanical floors) + inset glass core with per-window lighting + seed/param
// crown + context skyline. One sceneMap, one compute pass.
//
// Detail stack:  massing tiers -> facade cut -> glass core -> crown -> context.
// Precision:     every dimension is a typed parameter (analytic SDF, no mesh).

#include "../../modules/_shared/sdf/sdf_ops.hlsli"
#include "../../modules/_shared/sdf/sdf_shading.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

#define MAT_GROUND   0.0
#define MAT_STRUCT   1.0
#define MAT_GLASS    2.0
#define MAT_METAL    3.0
#define MAT_EMISSIVE 4.0
#define MAT_CONTEXT  5.0
#define MAT_CROWN    6.0

// ---- 2D plan primitives -------------------------------------------------------
float sd_box2(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float plan_dist(float2 p, int shape, float hw)
{
    if (shape == 0) return sd_box2(p, float2(hw, hw));                 // Square
    if (shape == 1) return sd_box2(p, float2(hw * 1.4, hw * 0.62));    // Slab
    if (shape == 2)                                                    // Chamfered (octagon)
    {
        float b = sd_box2(p, float2(hw, hw));
        float o = dot(abs(p), float2(0.7071, 0.7071)) - hw * 1.28;
        return max(b, o);
    }
    if (shape == 3)                                                    // Cross
        return min(sd_box2(p, float2(hw, hw * 0.42)), sd_box2(p, float2(hw * 0.42, hw)));
    return length(p) - hw;                                             // Round
}

// extrude a 2D plan distance to a Y-slab centred at yc, half-height hh
float extrude_y(float planD, float py, float yc, float hh)
{
    float2 w = float2(planD, abs(py - yc) - hh);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

// ---- massing: stacked seed-driven setback tiers -------------------------------
float massing_dist(float3 p, out float topY, out float topHW)
{
    float sd = (float)seed;
    int N = clamp(setbacks, 2, 6);
    int shape;
    if (plan_shape == 0)                                    // Auto: bias to buildable plans
    {
        float hs = sd_hash11(sd * 1.7);
        shape = (hs < 0.55) ? 0 : ((hs < 0.82) ? 2 : 3);   // Square / Chamfered / Cross
    }
    else shape = plan_shape - 1;

    float H = tower_height;
    float curW = base_width * 0.5;
    float curY0 = 0.0;
    float th = H * 0.42;                                    // base tier is the tallest
    float d = 1e9;

    topY = H;
    topHW = curW;

    [loop]
    for (int i = 0; i < 6; i++)
    {
        if (i >= N) break;
        float remH = H - curY0;
        float useH = min(th, remH);
        if (useH < 0.2) break;
        float yc = curY0 + useH * 0.5;

        float pd = plan_dist(p.xz, shape, curW);
        d = min(d, extrude_y(pd, p.y, yc, useH * 0.5));

        topY = curY0 + useH;
        topHW = curW;

        curY0 += useH;
        curW *= (0.82 + 0.07 * sd_hash11(sd * (float)(i + 3) + 1.3));       // gentle setback
        curW *= (1.0 - taper * 0.10);                                       // global taper
        th  *= (0.70 + 0.10 * sd_hash11(sd * (float)(i * 2 + 5) + 2.1));    // each tier shorter
        if (curY0 > H - 0.1) break;
    }
    return d;
}

// ---- facade: horizontal ribbon window bands (phase-independent) ---------------
// Punched windows on a global grid blank an entire face whenever a tier's width
// puts its wall between window columns. Ribbon bands span the full face, so every
// floor always reads. Vertical mullions + per-window lighting are done in shading.
// Returns a signed distance: < 0 means "inside the window band" (carved recess).
float facade_cut(float3 p)
{
    float fh = floor_height;
    if (p.y < fh * 2.5) return 1e9;                 // solid podium / ground floors
    float fy = floor(p.y / fh);
    float ly = (frac(p.y / fh) - 0.5) * fh;         // world-y within the floor
    bool mech = (((int)abs(fy)) % max(mech_every, 2)) == 0;
    float wy = fh * (mech ? 0.20 : window_h_ratio) * 0.5;   // mech floor = thin louver band
    return abs(ly) - wy;                            // horizontal ribbon slot
}

// ---- crown: seed- or param-selected top ---------------------------------------
float2 crown_sdf(float3 p, float topY, float hw)
{
    float sd = (float)seed;
    int st = (crown_style == 0) ? (1 + (int)(sd_hash11(sd * 4.4) * 2.999)) : crown_style;
    float3 base = float3(0.0, topY, 0.0);
    float2 r = float2(1e9, MAT_METAL);

    if (st == 1)                                     // Spire + beacon
    {
        float3 tip = base + float3(0.0, spire_height, 0.0);
        float sp = sd_rcone(p, base, tip, hw * 0.5, 0.02);
        float ant = sd_capsule(p, tip, tip + float3(0.0, 0.45, 0.0), 0.015);
        r = float2(min(sp, ant), MAT_METAL);
        float beacon = sd_sphere(p - (tip + float3(0.0, 0.47, 0.0)), 0.045);
        r = op_matmin(r, float2(beacon, MAT_EMISSIVE));
    }
    else if (st == 2)                                // Stepped glowing cap
    {
        float c1 = extrude_y(sd_box2(p.xz, float2(hw * 0.82, hw * 0.82)), p.y, topY + 0.16, 0.16);
        float c2 = extrude_y(sd_box2(p.xz, float2(hw * 0.52, hw * 0.52)), p.y, topY + 0.44, 0.14);
        r = float2(min(c1, c2), MAT_STRUCT);
        float band = extrude_y(sd_box2(p.xz, float2(hw * 0.86, hw * 0.86)), p.y, topY + 0.31, 0.022);
        r = op_matmin(r, float2(band, MAT_CROWN));
        float mast = sd_capsule(p, float3(0, topY + 0.58, 0), float3(0, topY + 0.95, 0), 0.014);
        r = op_matmin(r, float2(mast, MAT_METAL));
    }
    else                                             // Mech deck + water tower
    {
        float deck = extrude_y(sd_box2(p.xz, float2(hw * 0.92, hw * 0.92)), p.y, topY + 0.06, 0.06);
        float box1 = sd_rbox(p - float3(hw * 0.35, topY + 0.20, 0.0), float3(hw * 0.28, 0.12, hw * 0.42), 0.01);
        float wt = sd_cyl(p - float3(-hw * 0.32, topY + 0.26, 0.0), 0.18, 0.16);
        float wtc = sd_cone(p - float3(-hw * 0.32, topY + 0.50, 0.0), 0.09, 0.17, 0.02);
        r = float2(min(deck, min(box1, min(wt, wtc))), MAT_METAL);
    }
    return r;
}

// ---- context skyline: hashed low blocks in a bounded ring behind the hero -----
float2 context_sdf(float3 p)
{
    float2 c = float2(2.3, 2.3);
    float2 id = round(p.xz / c);
    float dist = length(id * c);
    if (dist < 6.0 || dist > context_radius) return float2(1e9, MAT_CONTEXT);  // ring only
    float3 rp = p;
    rp.xz = p.xz - c * id;
    float hh = (0.5 + 2.1 * sd_hash21(id)) * context_amount;                   // subordinate height
    float bw = 0.55 + 0.32 * sd_hash21(id + 7.3);
    float b = sd_rbox(rp - float3(0.0, hh, 0.0), float3(bw, hh, bw), 0.02);
    return float2(b, MAT_CONTEXT);
}

// ---- the scene (contract for sdf_shading.hlsli) -------------------------------
float2 sceneMap(float3 p)
{
    float2 res = float2(p.y, MAT_GROUND);            // ground plane

    float3 tp = p;
    if (twist != 0.0)
        tp.xz = sd_rot2(p.xz, twist * (p.y / max(tower_height, 0.1)));

    float topY, topHW;
    float raw = massing_dist(tp, topY, topHW);
    float cut = facade_cut(tp);
    float structure = max(raw, -cut);                // carved masonry shell
    float glass = raw + window_inset;                // shrunk solid = recessed panes

    res = op_matmin(res, float2(structure, MAT_STRUCT));
    res = op_matmin(res, float2(glass, MAT_GLASS));
    res = op_matmin(res, crown_sdf(tp, topY, topHW));

    if (context_amount > 0.01)
        res = op_matmin(res, context_sdf(p));

    return res;
}

// ---- window cell lighting + vertical mullions ---------------------------------
// Returns lit/dark per window cell in .x (1/0) and a mullion mask in .y
// (0 on the vertical mullion line, 1 in the pane center).
float2 window_cell(float3 pos, float3 n)
{
    float3 tp = pos;
    if (twist != 0.0)
        tp.xz = sd_rot2(pos.xz, twist * (pos.y / max(tower_height, 0.1)));
    float fy = floor(tp.y / floor_height);
    bool xface = abs(n.x) > abs(n.z);
    float along = (xface ? tp.z : tp.x) / window_pitch;   // face-tangent axis
    float col = floor(along);
    float face = xface ? 0.0 : 37.0;

    float lit = (sd_hash21(float2(col + face, fy)) < lit_ratio) ? 1.0 : 0.0;
    float edge = abs(frac(along) - 0.5);                  // 0 at mullion, 0.5 at pane center
    float mull = smoothstep(0.0, 0.11, edge);             // dark vertical mullion line
    // pier columns (every Nth) read as a wider mullion
    if ((((int)abs(col)) % max(pier_every, 2)) == 0) mull *= 0.35;
    return float2(lit, mull);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = (uv * 2.0 - 1.0) * float2(_Resolution.x / _Resolution.y, -1.0);

    float3 ro, rd;
    if (use_fly_cam != 0)
    {
        ro = _CameraPos;
        rd = _RayDirection(uv);
    }
    else
    {
        float az = cam_orbit + rotate_speed * _Time * 24.0;
        sdf_orbitRay(az, cam_elevation, cam_distance,
                     float3(0.0, cam_target_y, 0.0), ndc, 1.7, ro, rd);
    }

    float3 sun = sdf_sunDir(sun_azimuth, sun_elevation);
    float dn = day_night;

    // sky
    float3 zen = lerp(float3(0.02, 0.03, 0.07), float3(0.33, 0.52, 0.85), dn);
    float3 hor = lerp(float3(0.10, 0.09, 0.15), float3(0.74, 0.81, 0.90), dn);
    float3 sky = lerp(hor, zen, saturate(rd.y * 1.3 + 0.15));
    sky += pow(saturate(dot(rd, sun)), 48.0) * lerp(float3(0.55, 0.32, 0.14), float3(0.95, 0.86, 0.66), dn);

    // march (tight threshold for crisp facade detail)
    float stepScale = (twist != 0.0) ? 0.6 : 0.9;
    float t = 0.0;
    float matId = -1.0;
    [loop]
    for (int i = 0; i < 220; i++)
    {
        float3 pos = ro + rd * t;
        float2 h = sceneMap(pos);
        if (h.x < 0.0004 * t + 0.00015) { matId = h.y; break; }
        t += h.x * stepScale;
        if (t > 90.0) break;
    }

    float3 col = sky;
    if (matId >= -0.5)
    {
        float3 pos = ro + rd * t;
        float3 n = sdf_calcNormal(pos);
        float ao = sdf_calcAO(pos, n);
        int m = (int)floor(matId + 0.5);

        float sunI = lerp(0.28, 1.0, dn);
        float sha = 1.0;
        if (shadows != 0)
            sha = lerp(0.5, sdf_softShadow(pos + n * 0.01, sun, 10.0, 20.0), 0.85);

        if (m == MAT_EMISSIVE)
        {
            col = float3(1.0, 0.24, 0.16) * (1.4 + 0.6 * sin(_Time * 3.2));   // beacon pulse
        }
        else if (m == MAT_CROWN)
        {
            float3 e = emissive_color * (0.6 + 0.9 * dn * 0.0 + 0.9 * (1.0 - dn));
            col = lerp(sdf_shade(emissive_color * 0.5, n, rd, sun, sha, ao, 0.3, 24.0), emissive_color * 1.6, 1.0 - dn);
        }
        else if (m == MAT_GLASS)
        {
            float2 wc = window_cell(pos, n);
            float lit = wc.x;
            float mull = wc.y;
            float fres = pow(1.0 - saturate(dot(n, -rd)), 4.0);
            if (dn > 0.5)   // day: reflective curtain wall with mullion grid
            {
                float3 g = glass_color * (0.18 + 0.7 * saturate(dot(n, sun)) * sha) * ao;
                col = lerp(g, sky * 1.05, saturate(fres + 0.25));
                col *= 0.35 + 0.65 * mull;                 // mullion lines darken
            }
            else            // dusk/night: individual lit windows
            {
                if (lit > 0.5)
                    col = emissive_color * (1.3 + 0.5 * sd_hash21(floor(pos.xz * 5.0))) * (0.25 + 0.75 * mull);
                else
                    col = glass_color * 0.14 * ao + sky * fres * 0.45;
            }
        }
        else
        {
            float3 albedo;
            float specAmt, specPow;
            if (m == MAT_GROUND)
            {
                albedo = float3(0.05, 0.05, 0.06);
                float2 gp = abs(frac(pos.xz / 1.0) - 0.5) * 2.0;
                float ln = 1.0 - smoothstep(0.0, 0.06, min(gp.x, gp.y));
                albedo *= 1.0 - ln * 0.4;
                specAmt = 0.05; specPow = 12.0;
            }
            else if (m == MAT_STRUCT) { albedo = structure_color;              specAmt = 0.22; specPow = 22.0; }
            else if (m == MAT_METAL)  { albedo = float3(0.33, 0.35, 0.40);     specAmt = 0.85; specPow = 46.0; }
            else                      { albedo = structure_color * 0.35;       specAmt = 0.10; specPow = 14.0; } // context

            float3 lit = sdf_shade(albedo, n, rd, sun, sha, ao, specAmt, specPow) * sunI;
            // ambient sky fill
            lit += albedo * lerp(float3(0.04, 0.05, 0.08), float3(0.12, 0.14, 0.18), dn) * ao;
            col = lit;

            // context towers get a few lit windows at night, cheaply
            if (m == MAT_CONTEXT && dn < 0.5)
            {
                float w = sd_hash21(floor(pos.xz * 6.0) + floor(pos.y * 4.0));
                if (w < 0.12 * (1.0 - dn)) col += emissive_color * 0.7;
            }
        }

        float fog = 1.0 - exp(-fog_density * 0.05 * max(t - 3.0, 0.0));
        col = lerp(col, sky, fog);
    }

    col = pow(saturate(col), 0.90);
    OutputUAV[pixel] = float4(col, 1.0);
}
