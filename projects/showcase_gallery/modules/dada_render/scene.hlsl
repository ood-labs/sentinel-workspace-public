// dada_render — data-driven surreal renderer for desert_totem v2. Marches two DadaPart
// buffers (totem props on data:0, scatter accents on data:1) in ONE depth domain with a
// hardcoded armature + wires, plus domain distortion (melt / sag / mirror), painterly
// surface, and a full painterly-surreal desert-mountain horizon. Fly/orbit camera.

#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/sdf/sdf_extras.hlsli"
#include "../_shared/sdf/sdf_dada.hlsli"
#include "../_shared/sdf/sdf_shading.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct DadaPart {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float p0; float p1; float p2; float active;
};

static float3 g_camPos = float3(0, 0, 0);
float3 sd_rotZ(float3 p, float a) { p.xy = sd_rot2(p.xy, a); return p; }

// ---- value noise / fbm --------------------------------------------------------
float vnoise2(float2 p)
{
    float2 i = floor(p); float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sd_hash21(i);
    float b = sd_hash21(i + float2(1, 0));
    float c = sd_hash21(i + float2(0, 1));
    float d = sd_hash21(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}
float fbm2(float2 p)
{
    float s = 0.0, a = 0.5;
    // Keep the octave body as one runtime loop. This function is called from
    // sceneMap-adjacent code, so static expansion makes a cold FXC compile grow
    // disproportionately even though the runtime work is unchanged.
    [loop]
    for (int i = 0; i < 5; i++) { s += a * vnoise2(p); p *= 2.02; a *= 0.5; }
    return s;
}

// ---- material palette ---------------------------------------------------------
#define M_GROUND 0.0
#define M_WOOD   1.0
#define M_BLACK  2.0
#define M_WHITE  3.0

float3 woodAlbedo(float3 p)
{
    float g   = fbm2(float2(p.x * 1.1 + p.z * 0.2, p.z * 0.5 + p.y * 0.3));
    float ring = frac(g * 3.0 + p.x * 0.55 + p.z * 0.15);
    float streak = smoothstep(0.15, 0.85, ring * 0.55 + g * 0.45);
    return lerp(float3(0.30, 0.19, 0.10), float3(0.56, 0.41, 0.24), streak);
}
float3 groundAlbedo(float3 p)
{
    float g = fbm2(p.xz * 0.6);
    return lerp(float3(0.80, 0.72, 0.57), float3(0.86, 0.79, 0.65), g);
}
// procedural "photograph" — a tiny desert-mountain landscape painted into a panel,
// the surrealist collage-inset move. uv derived from the panel-local frame passed in p.
#define M_PHOTO 30.0
float3 photoAlbedo(float2 uv)
{
    float3 sky = lerp(float3(0.72, 0.78, 0.86), float3(0.30, 0.50, 0.74), saturate(uv.y));
    float ridge = 0.40 + 0.16 * fbm2(float2(uv.x * 3.2, 1.0)) + 0.06 * fbm2(float2(uv.x * 9.0, 4.0));
    float m = smoothstep(ridge + 0.02, ridge - 0.02, uv.y);
    float3 mtn = lerp(float3(0.42, 0.40, 0.46), float3(0.60, 0.55, 0.52), fbm2(uv * 6.0));
    float3 grd = lerp(float3(0.74, 0.66, 0.48), float3(0.60, 0.50, 0.34), fbm2(uv * 5.0));
    float g = smoothstep(0.30, 0.26, uv.y);                 // ground band at the bottom
    float3 c = lerp(sky, mtn, m);
    return lerp(c, grd, g);
}

float3 matAlbedo(float mat, float3 p)
{
    if (mat < 0.5) return groundAlbedo(p);
    if (mat < 1.5) return woodAlbedo(p);
    if (mat < 2.5) return float3(0.018, 0.018, 0.022);
    if (mat < 3.5) return float3(0.945, 0.935, 0.905);
    if (mat < 10.5) return float3(0.86, 0.13, 0.09);
    if (mat < 11.5) return float3(0.95, 0.75, 0.10);
    if (mat < 12.5) return float3(0.90, 0.40, 0.08);
    if (mat < 13.5) return float3(0.48, 0.52, 0.24);
    if (mat < 14.5) return float3(0.52, 0.53, 0.55);
    if (mat < 15.5) return float3(0.020, 0.020, 0.024);
    if (mat < 16.5) return float3(0.955, 0.945, 0.915);
    return float3(0.85, 0.66, 0.24);
}
float2 matSpec(float mat)
{
    if (mat > 29.5) return float2(0.05, 18.0);   // photo panel (matte)
    if (mat < 0.5) return float2(0.02, 16.0);
    if (mat < 1.5) return float2(0.04, 18.0);
    if (mat < 2.5) return float2(0.03, 24.0);
    if (mat < 3.5) return float2(0.07, 26.0);
    if (mat < 13.5) return float2(0.09, 26.0);
    if (mat < 14.5) return float2(0.20, 40.0);
    if (mat < 15.5) return float2(0.22, 44.0);
    if (mat < 16.5) return float2(0.20, 40.0);
    return float2(0.72, 42.0);
}

// ---- hardcoded armature + wires (not data-driven) -----------------------------
float2 mapStructure(float3 p)
{
    float3 bq = p - float3(0.0, 0.15, 0.35);
    bq.xz = sd_rot2(bq.xz, board_yaw);
    float2 res = float2(sd_box(bq, float3(3.1, 0.14, 1.75)), M_WOOD);
    float spine = sd_box(p - float3(0.0, 1.05 + spine_height, -0.15), float3(0.80, spine_height, 0.28));
    float panel = sd_box(p - float3(0.0, 6.60, -0.20), float3(1.34, 1.42, 0.24));
    float cross = sd_box(p - float3(0.0, 3.55, -0.12), float3(1.95, 0.30, 0.32));
    res = op_matmin(res, float2(min(spine, min(panel, cross)), M_BLACK));
    float shelf  = sd_rbox(p - float3(0.15, 3.60, 0.60), float3(2.15, 0.055, 0.95), 0.015);
    float plinth = sd_rbox(p - float3(-1.70, 2.25, 0.30), float3(0.52, 1.15, 0.55), 0.03);
    res = op_matmin(res, float2(min(shelf, plinth), M_WHITE));
    // photo-collage inset panel on the plinth (procedural desert-mountain "photo")
    float photo = sd_rbox(p - float3(-1.70, 2.85, 0.92), float3(0.55, 0.72, 0.03), 0.02);
    res = op_matmin(res, float2(photo, M_PHOTO));
    return res;
}

// (background mini-totems are drawn cheaply as horizon silhouettes in skyColor)
float2 mapWires(float3 p)
{
    float3 mastTop = float3(-2.55, 7.75, -0.05);
    float mast = sd_capsule(p, float3(-1.55, 3.75, 0.20), mastTop, 0.03);
    float ps1 = sd_capsule(p, float3(-2.05, 3.30, 0.05), float3(-2.35, 2.70, 0.05), 0.012);
    float ps2 = sd_capsule(p, float3(-2.35, 2.70, 0.05), float3(-2.35, 1.92, 0.05), 0.012);
    float ps3 = sd_capsule(p, float3(-2.35, 1.92, 0.05), float3(-2.35, 1.20, 0.05), 0.012);
    float2 res = float2(min(mast, min(ps1, min(ps2, ps3))), M_BLACK);
    float rig1 = sd_bezierTube(p, mastTop, float3(-1.1, 6.0, 0.3), float3(-0.1, 4.0, 0.6), 0.012);
    float rig2 = sd_bezierTube(p, mastTop, float3(-3.0, 5.8, 0.2), float3(-2.3, 3.9, 0.4), 0.012);
    res = op_matmin(res, float2(min(rig1, rig2), 17.0));
    float rod = sd_capsule(p, float3(1.75, 5.55, 0.30), float3(1.75, 6.90, 0.30), 0.022);
    float arc = sd_bezierTube(p, float3(1.15, 0.55, 0.45), float3(2.75, 1.35, 0.15), float3(2.05, 0.15, 0.55), 0.03);
    res = op_matmin(res, float2(min(rod, arc), 14.0));
    return res;
}

// ---- domain distortion toolkit ------------------------------------------------
// one warp field, selectable character (mode), at frequency f and phase t.
float3 warpFieldMode(float3 p, int mode, float f, float t)
{
    if (mode == 1)                                         // Ripple (radial)
    {
        float r = length(p.xz) + 1e-3;
        float w = sin(r * f * 2.0 - t * 2.0);
        return float3(p.x / r * w, sin(p.y * f + t), p.z / r * w) * 0.6;
    }
    if (mode == 2)                                         // Turbulent
        return float3(sin(p.y * f + t), cos(p.x * f - t), sin(p.z * f + t * 1.3));
    if (mode == 3)                                         // Fractal (2 octaves)
    {
        float3 w = float3(sin(p.y * f + t), sin(p.z * f * 1.3 + t), sin(p.x * f * 0.7 - t));
        w += 0.5 * float3(sin(p.y * f * 2.1 + t * 1.7), sin(p.z * f * 2.3 - t), sin(p.x * f * 1.9 + t));
        return w;
    }
    if (mode == 4)                                         // Steps — terraced (rectilinear)
    {
        float3 s = float3(sin(p.y * f + t), sin(p.z * f * 1.2 - t), sin(p.x * f * 0.8 + t));
        return lerp(s, round(s * 3.0) / 3.0, 0.85);        // mostly stepped, slightly smoothed for march safety
    }
    if (mode == 5)                                         // Boxes — soft square wave (blocky)
    {
        float3 s = float3(sin(p.y * f + t), sin(p.x * f - t), sin(p.z * f * 1.3 + t));
        return clamp(s * 4.0, -1.0, 1.0) * 0.7;            // flat plateaus, steep sides -> rectilinear pushes
    }
    if (mode == 6)                                         // Shatter — per-grid-cell constant offset (cubist)
    {
        float3 cell = floor(p * f * 0.6 + t * 0.1);
        float3 h = float3(frac(sin(dot(cell, float3(12.9, 78.2, 37.7))) * 43758.5),
                          frac(sin(dot(cell, float3(39.3, 11.1, 83.2))) * 24634.6),
                          frac(sin(dot(cell, float3(73.1, 52.7,  9.7))) * 13451.2)) - 0.5;
        return h * 1.4;                                    // piecewise-constant per block
    }
    return float3(                                          // Flow (default)
        sin(p.y * f + t)       + 0.5 * sin(p.z * f * 1.7 - t * 1.3),
        sin(p.z * f * 0.9 + t) + 0.5 * sin(p.x * f * 1.5 + t * 1.1),
        sin(p.x * f * 1.1 - t) + 0.5 * sin(p.y * f * 1.3 + t * 0.7));
}

// one warp SLOT: sample the field in a rotated + offset frame, return the (weighted)
// displacement back in world orientation. Off when amt ~ 0.
float3 warpLayer(float3 p, float amt, int mode, float f, float spd, float3 off, float yaw, float pitch)
{
    if (amt < 0.001) return float3(0.0, 0.0, 0.0);
    float3 q = p - off;
    q = sd_rotY(q, yaw);
    q = sd_rotX(q, pitch);
    float3 d = warpFieldMode(q, mode, f, _Time * spd);
    d = sd_rotX(d, -pitch);
    d = sd_rotY(d, -yaw);
    return amt * d;
}

// distort the solids' domain (ground stays flat). Each op is gated by its amount.
float3 domainDistort(float3 p)
{
    float3 c = float3(dist_cx, dist_cy, dist_cz);
    float3 q = p;
    float h = q.y - c.y;

    if (abs(twist_amt) > 0.001)                            // twist about Y by height
        q.xz = sd_rot2(q.xz - c.xz, twist_amt * h * 0.35) + c.xz;
    if (abs(bend_amt) > 0.001)                             // bend / arc the tower
        q.x += bend_amt * h * h * 0.06;
    if (abs(swirl_amt) > 0.001)                            // swirl, strongest at centre
    {
        float2 d = q.xz - c.xz;
        q.xz = sd_rot2(d, swirl_amt * exp(-length(d) * 0.4)) + c.xz;
    }
    if (sag_amt > 0.001)                                   // gravity droop
    {
        float horiz = length(float2(q.x, q.z - 0.1));
        q.y -= sag_amt * horiz * smoothstep(1.0, 7.5, q.y) * 0.9;
    }
    if (wave_amt > 0.001)                                  // sinusoidal ripple
        q += wave_amt * sin(q.yzx * wave_freq + _Time * warp_speed) * 0.3;
    if (abs(pinch_amt) > 0.001)                            // pinch / inflate radially
    {
        float2 d = q.xz - c.xz;
        q.xz = c.xz + d * (1.0 + pinch_amt * (1.0 - saturate(length(d) * 0.3)));
    }
    if (mirror_count > 0.5)                                // mirror / radial kaleidoscope
    {
        float2 d = float2(q.x, q.z - 0.2);
        if (mirror_mode == 1) d.x = abs(d.x);              // Mirror X
        else
        {
            float a = atan2(d.y, d.x);
            float seg = 6.28318530 / mirror_count;
            a = (abs(frac(a / seg + 0.5) - 0.5)) * seg;
            float r = length(d);
            d = float2(cos(a) * r, sin(a) * r);
        }
        q.x = d.x; q.z = d.y + 0.2;
    }
    if (melt_amt > 0.001)                                  // 3-slot warp stack
    {
        float3 disp = warpLayer(q, w1_amt, w1_mode, w1_freq, w1_speed, float3(w1_ox, w1_oy, w1_oz), w1_yaw, w1_pitch)
                    + warpLayer(q, w2_amt, w2_mode, w2_freq, w2_speed, float3(w2_ox, w2_oy, w2_oz), w2_yaw, w2_pitch)
                    + warpLayer(q, w3_amt, w3_mode, w3_freq, w3_speed, float3(w3_ox, w3_oy, w3_oz), w3_yaw, w3_pitch);
        q += melt_amt * disp;
    }

    return q;
}

// Lipschitz safety factor — under-steps the marcher in proportion to how much the
// active distortions inflate the distance gradient (prevents overshoot / TDR).
float distortLip()
{
    float warpF = melt_amt * (w1_amt * w1_freq + w2_amt * w2_freq + w3_amt * w3_freq) * 0.5;
    return 1.0 / (1.0 + warpF + sag_amt * 0.6
                + wave_amt * wave_freq * 0.25 + abs(twist_amt) * 0.4
                + abs(swirl_amt) * 0.3 + abs(pinch_amt) * 0.5 + abs(bend_amt) * 0.3
                + (mirror_count > 0.5 ? 0.2 : 0.0));
}

// hue rotation for the surface hue-shift control
float3 hueRotate(float3 col, float a)
{
    float3 k = float3(0.57735, 0.57735, 0.57735);
    float cs = cos(a), sn = sin(a);
    return col * cs + cross(k, col) * sn + k * dot(k, col) * (1.0 - cs);
}

// ---- instance helpers --------------------------------------------------------
float3 partLocal(DadaPart d, float3 p, out float minsc)
{
    float3 q = p - float3(d.pos_xy.x, d.pos_xy.y, d.pos_z);
    q = sd_rotY(q, -d.yaw); q = sd_rotX(q, -d.tilt); q = sd_rotZ(q, -d.roll);
    float3 sc = float3(d.sc_xy.x, d.sc_xy.y, d.sc_z);
    minsc = min(sc.x, min(sc.y, sc.z));
    return q / sc;
}
float partBand(DadaPart d) { return DADA_BOUND_R * max(d.sc_xy.x, max(d.sc_xy.y, d.sc_z)) + 0.06; }

// ---- the scene (contract for sdf_shading.hlsli) ------------------------------
float2 sceneMap(float3 p)
{
    float ground = p.y + 0.04 * fbm2(p.xz * 0.15) - 0.02;
    float2 res = float2(ground, M_GROUND);

    float3 pw = domainDistort(p);
    res = op_matmin(res, mapStructure(pw));
    res = op_matmin(res, mapWires(pw));

    uint c0 = min((uint)_Data0_Count, 128u);
    [loop]
    for (uint i = 0u; i < c0; i++)
    {
        DadaPart d = _Data0[i];
        if (d.active < 0.5) continue;
        if (abs(pw.y - d.pos_xy.y) > partBand(d)) continue;
        float minsc; float3 q = partLocal(d, pw, minsc);
        res = op_matmin(res, float2(dada_obj(q, (int)d.kind, d.p0, d.p1, d.p2) * minsc, 20.0 + d.kind));
    }
    uint c1 = min((uint)_Data1_Count, 128u);
    [loop]
    for (uint j = 0u; j < c1; j++)
    {
        DadaPart d = _Data1[j];
        if (d.active < 0.5) continue;
        if (abs(pw.y - d.pos_xy.y) > partBand(d)) continue;
        float minsc; float3 q = partLocal(d, pw, minsc);
        res = op_matmin(res, float2(dada_obj(q, (int)d.kind, d.p0, d.p1, d.p2) * minsc, 20.0 + d.kind));
    }

    res.x *= distortLip();   // Lipschitz safety for the warped field
    return res;
}

// nearest-surface colour, once per hit pixel
void shadeSample(float3 pos, out float3 albedo, out float2 spec)
{
    float3 pw = domainDistort(pos);
    float ground = pos.y + 0.04 * fbm2(pos.xz * 0.15) - 0.02;
    float2 sres = float2(ground, M_GROUND);
    sres = op_matmin(sres, mapStructure(pw));
    sres = op_matmin(sres, mapWires(pw));
    float best = sres.x;
    if (sres.y > 29.5)             // photo panel — heavy fbm computed once, not in loops
    {
        float2 uv = float2((pos.x + 2.25) / 1.10, (pos.y - 2.13) / 1.44);
        albedo = photoAlbedo(uv);
    }
    else albedo = matAlbedo(sres.y, pos);
    spec = matSpec(sres.y);

    uint c0 = min((uint)_Data0_Count, 128u);
    [loop]
    for (uint i = 0u; i < c0; i++)
    {
        DadaPart d = _Data0[i];
        if (d.active < 0.5) continue;
        if (abs(pw.y - d.pos_xy.y) > partBand(d)) continue;
        float minsc; float3 q = partLocal(d, pw, minsc);
        float dd = dada_obj(q, (int)d.kind, d.p0, d.p1, d.p2) * minsc;
        if (dd < best) { best = dd; float3 sc; if (dada_special_albedo((int)d.kind, q, d.p0, d.p1, d.p2, sc)) albedo = sc; else albedo = matAlbedo(d.mat, pos); spec = matSpec(d.mat); }
    }
    uint c1 = min((uint)_Data1_Count, 128u);
    [loop]
    for (uint j = 0u; j < c1; j++)
    {
        DadaPart d = _Data1[j];
        if (d.active < 0.5) continue;
        if (abs(pw.y - d.pos_xy.y) > partBand(d)) continue;
        float minsc; float3 q = partLocal(d, pw, minsc);
        float dd = dada_obj(q, (int)d.kind, d.p0, d.p1, d.p2) * minsc;
        if (dd < best) { best = dd; float3 sc; if (dada_special_albedo((int)d.kind, q, d.p0, d.p1, d.p2, sc)) albedo = sc; else albedo = matAlbedo(d.mat, pos); spec = matSpec(d.mat); }
    }
}

// ---- surreal desert-mountain horizon -----------------------------------------
float3 skyColor(float3 rd)
{
    float3 zen = lerp(sky_zenith.rgb, float3(0.28, 0.48, 0.70), 0.5);   // deeper blue
    float3 hor = sky_horizon.rgb;
    float3 col = lerp(hor, zen, pow(saturate(rd.y), 0.55));

    float az = atan2(rd.z, rd.x);
    // three atmospheric mountain ridges, far -> near
    [loop]
    for (int L = 0; L < 3; L++)
    {
        float fl = 1.6 + L * 2.4;
        float amp = 0.055 - L * 0.013;
        float base = 0.052 - L * 0.016;
        float ridge = base + (fbm2(float2(az * fl, L * 3.7 + 2.0)) - 0.5) * amp * 2.0;
        float m = smoothstep(ridge + 0.004, ridge - 0.004, rd.y) * smoothstep(-0.16, 0.0, rd.y);
        float3 mcol = lerp(float3(0.50, 0.57, 0.70), hor, 0.72 - L * 0.26);
        col = lerp(col, mcol, m);
    }
    // distant wrong-scale mini-totems on the horizon (cheap silhouettes: bar + top ball)
    float sil = 0.0;
    [loop]
    for (int f = 0; f < 5; f++)
    {
        float fa = -1.35 + f * 0.62;
        float da = az - fa;
        float w = 0.008 + 0.004 * fbm2(float2(fa * 5.0, 2.0));
        float bodyH = 0.024 + 0.016 * fbm2(float2(fa * 3.0, 7.0));   // wrong-scale height
        float bar = smoothstep(w, w * 0.55, abs(da))
                  * smoothstep(bodyH, bodyH - 0.003, rd.y)
                  * smoothstep(-0.002, 0.0015, rd.y);
        float ball = smoothstep(w * 2.2, 0.0, length(float2(da, (rd.y - bodyH) * 1.1)));
        sil = max(sil, max(bar, ball));
    }
    col = lerp(col, float3(0.20, 0.19, 0.23), saturate(sil) * 0.8);
    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = (uv * 2.0 - 1.0) * float2(_Resolution.x / _Resolution.y, -1.0);

    float3 ro, rd;
    if (cam_mode == 0)
    {
        float2 ndcv = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
        float4 nearW = mul(_InvViewProjMatrix, float4(ndcv, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndcv, 1.0, 1.0));
        nearW /= nearW.w; farW /= farW.w;
        ro = _CameraPos; rd = normalize(farW.xyz - nearW.xyz);
    }
    else
    {
        float az = cam_orbit + rotate_speed * _Time * 30.0;
        sdf_orbitRay(az, cam_elevation, cam_distance, float3(0.0, cam_target_y, 0.0), ndc, cam_focal, ro, rd);
    }
    g_camPos = ro;

    float3 sun = sdf_sunDir(sun_azimuth, sun_elevation);
    float3 haze = lerp(sky_horizon.rgb, float3(0.86, 0.83, 0.76), 0.5);

    float mat;
    float t = sdf_march(ro, rd, march_dist, 140, mat);

    float3 col;
    if (t < 0.0)
    {
        // heat-haze shimmer near the horizon
        float3 rr = rd;
        float hz = smoothstep(0.16, 0.0, abs(rd.y)) * heat_amt;
        rr.y += sin(rd.x * 46.0 + _Time * 3.0) * 0.0025 * hz;
        col = skyColor(rr);
    }
    else
    {
        float3 pos = ro + rd * t;
        float3 n = sdf_calcNormal(pos);
        float ao = sdf_calcAO(pos, n);
        float sha = 1.0;
        if (shadows != 0) sha = sdf_softShadow(pos + n * 0.02, sun, 16.0, 24.0);

        float3 albedo; float2 sp;
        shadeSample(pos, albedo, sp);

        // ---- surface distortion toolkit ----
        float ps = painterly_scale;
        if (facet_amt > 0.001)                                  // low-poly / crystalline facets
        {
            float k = lerp(24.0, 3.0, saturate(facet_amt));
            n = normalize(floor(n * k + 0.5) / k + 1e-4);
        }
        if (painterly_amt > 0.001 || wobble_amt > 0.001)        // hand-made + animated surface
        {
            float ta = _Time * 1.5 * wobble_amt;
            float3 rnd = float3(fbm2(pos.xy * ps + ta) - 0.5,
                                fbm2(pos.yz * ps + 3.1 - ta) - 0.5,
                                fbm2(pos.zx * ps + 7.7 + ta) - 0.5);
            n = normalize(n + (painterly_amt * 0.35 + wobble_amt * 0.40) * rnd);
            albedo *= 1.0 - painterly_amt * 0.20 * (fbm2(pos.xz * ps * 1.3 + pos.y * 3.0) - 0.5) * 2.0;
        }
        if (hue_shift > 0.001)                                  // psychedelic hue rotation up the tower
            albedo = saturate(hueRotate(albedo, hue_shift * 6.2831 + pos.y * 0.25));

        col = sdf_shade(albedo, n, rd, sun, sha, ao, sp.x, sp.y);
        float sky_up = saturate(0.5 + 0.5 * n.y);
        col += albedo * sky_zenith.rgb * sky_up * 0.10;
        col += albedo * float3(0.95, 0.80, 0.55) * 0.07 * saturate(0.35 - n.y) * ao;
        float fog = 1.0 - exp(-fog_density * 0.020 * max(t - 16.0, 0.0));
        col = lerp(col, haze, fog);
    }

    col = pow(saturate(col * exposure), 1.0 / 2.2);
    OutputUAV[pixel] = float4(col, 1.0);
}
