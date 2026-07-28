// blob_render — the glossy organic mass (strata plate 1). Marches a BlobPart buffer (data:0)
// as ONE op_smin-blended field: intertwined ribbons/blobs with 2-stop gradient gloss, chrome,
// and checker materials, on a TRANSPARENT background (premultiplied-alpha coverage matte) so
// it composites over the other plates. Domain-distortion warp toolkit is wired but defaults
// to zero — arrange it beautifully first, distort later. The renderer follows Sentinel's
// native internal-camera contract; every ray comes from the injected inverse view-projection.
//
// harvest note: the matte-aware SDF plate contract (premult RGBA coverage + SSAA edges) is
// the reusable technique here — any raymarch plate can adopt it to composite in 2D.

#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/palette.hlsli"
#include "../_shared/sdf/sdf_blob.hlsli"
#include "../_shared/sdf/sdf_shading.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct BlobPart {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float colA; float colB; float grad; float active;
};
// _Data0 / _Data0_Count are injected by the engine from the data:0 binding (schema =
// this struct); do NOT declare the buffer here (redefinition).

float3 sd_rotZ(float3 p, float a) { p.xy = sd_rot2(p.xy, a); return p; }

// ---- domain-distortion warp toolkit (ported from desert_totem dada_render) --------
float3 warpFieldMode(float3 p, int mode, float f, float t)
{
    if (mode == 1) { float r = length(p.xz) + 1e-3; float w = sin(r * f * 2.0 - t * 2.0);
        return float3(p.x / r * w, sin(p.y * f + t), p.z / r * w) * 0.6; }
    if (mode == 2) return float3(sin(p.y * f + t), cos(p.x * f - t), sin(p.z * f + t * 1.3));
    if (mode == 3) { float3 w = float3(sin(p.y * f + t), sin(p.z * f * 1.3 + t), sin(p.x * f * 0.7 - t));
        w += 0.5 * float3(sin(p.y * f * 2.1 + t * 1.7), sin(p.z * f * 2.3 - t), sin(p.x * f * 1.9 + t)); return w; }
    if (mode == 4) { float3 s = float3(sin(p.y * f + t), sin(p.z * f * 1.2 - t), sin(p.x * f * 0.8 + t));
        return lerp(s, round(s * 3.0) / 3.0, 0.85); }
    if (mode == 5) { float3 s = float3(sin(p.y * f + t), sin(p.x * f - t), sin(p.z * f * 1.3 + t));
        return clamp(s * 4.0, -1.0, 1.0) * 0.7; }
    if (mode == 6) { float3 cell = floor(p * f * 0.6 + t * 0.1);
        float3 h = float3(frac(sin(dot(cell, float3(12.9, 78.2, 37.7))) * 43758.5),
                          frac(sin(dot(cell, float3(39.3, 11.1, 83.2))) * 24634.6),
                          frac(sin(dot(cell, float3(73.1, 52.7, 9.7))) * 13451.2)) - 0.5; return h * 1.4; }
    return float3(sin(p.y * f + t) + 0.5 * sin(p.z * f * 1.7 - t * 1.3),
                  sin(p.z * f * 0.9 + t) + 0.5 * sin(p.x * f * 1.5 + t * 1.1),
                  sin(p.x * f * 1.1 - t) + 0.5 * sin(p.y * f * 1.3 + t * 0.7));
}
float3 warpLayer(float3 p, float amt, int mode, float f, float spd, float3 off, float yaw, float pitch)
{
    if (amt < 0.001) return float3(0, 0, 0);
    float3 q = p - off; q = sd_rotY(q, yaw); q = sd_rotX(q, pitch);
    float3 d = warpFieldMode(q, mode, f, _Time * spd);
    d = sd_rotX(d, -pitch); d = sd_rotY(d, -yaw);
    return amt * d;
}
float3 domainDistort(float3 p)
{
    float3 c = float3(dist_cx, dist_cy, dist_cz);
    float3 q = p; float h = q.y - c.y;
    if (abs(twist_amt) > 0.001) q.xz = sd_rot2(q.xz - c.xz, twist_amt * h * 0.35) + c.xz;
    if (abs(bend_amt) > 0.001)  q.x += bend_amt * h * h * 0.06;
    if (abs(swirl_amt) > 0.001) { float2 d = q.xz - c.xz; q.xz = sd_rot2(d, swirl_amt * exp(-length(d) * 0.4)) + c.xz; }
    if (wave_amt > 0.001)       q += wave_amt * sin(q.yzx * wave_freq + _Time * warp_speed) * 0.3;
    if (melt_amt > 0.001) {
        float3 disp = warpLayer(q, w1_amt, w1_mode, w1_freq, w1_speed, float3(w1_ox, w1_oy, w1_oz), w1_yaw, w1_pitch)
                    + warpLayer(q, w2_amt, w2_mode, w2_freq, w2_speed, float3(w2_ox, w2_oy, w2_oz), w2_yaw, w2_pitch);
        q += melt_amt * disp;
    }
    return q;
}
float distortLip()
{
    float warpF = melt_amt * (w1_amt * w1_freq + w2_amt * w2_freq) * 0.5;
    return 1.0 / (1.0 + warpF + wave_amt * wave_freq * 0.25 + abs(twist_amt) * 0.4
                + abs(swirl_amt) * 0.3 + abs(bend_amt) * 0.3);
}

// ---- quality budgets ---------------------------------------------------------
// Render Quality:
//   0 Draft       = fastest edit/arrangement view
//   1 Performance = safe live default
//   2 Fidelity    = original 130-step, 2x2 SSAA render
//   3 Custom      = explicit controls from the Quality/Custom group
int qualityMarchSteps()
{
    if (render_quality == 0) return 32;
    if (render_quality == 1) return 64;
    if (render_quality == 2) return 130;
    return clamp((int)march_steps, 32, 160);
}

uint qualityPartLimit()
{
    // Layout records are packed active-first. Draft deliberately renders the
    // nearest 24 authored parts; Performance keeps the complete current layout.
    if (render_quality == 0) return 24u;
    if (render_quality == 1) return 32u;
    if (render_quality == 2) return 128u;
    return (uint)clamp((int)part_limit, 4, 128);
}

float qualityMarchDistance()
{
    if (render_quality == 0) return 32.0;
    if (render_quality == 1) return 40.0;
    if (render_quality == 2) return 80.0;
    return clamp(march_dist, 10.0, 120.0);
}

float qualitySurfaceEpsilon()
{
    if (render_quality == 0) return 0.0016;
    if (render_quality == 1) return 0.0009;
    if (render_quality == 2) return 0.00045;
    return clamp(surface_epsilon, 0.0001, 0.004);
}

float qualityStepScale()
{
    if (render_quality == 0) return 1.0;
    if (render_quality == 1) return 0.9;
    if (render_quality == 2) return 0.72;
    return clamp(step_scale, 0.5, 1.0);
}

float qualityNormalEpsilon()
{
    if (render_quality == 0) return 0.0024;
    if (render_quality == 1) return 0.0012;
    if (render_quality == 2) return 0.00065;
    return clamp(normal_epsilon, 0.0002, 0.006);
}

int qualityAOSamples()
{
    if (render_quality == 0) return 0;
    if (render_quality == 1) return 2;
    if (render_quality == 2) return 5;
    return clamp((int)ao_samples, 0, 5);
}

int qualityShadowSteps()
{
    if (render_quality == 0) return 0;
    if (render_quality == 1) return 12;
    if (render_quality == 2) return 48;
    return clamp((int)shadow_steps, 0, 48);
}

int qualityAA()
{
    if (render_quality <= 1) return 1;
    if (render_quality == 2) return 2;
    return clamp((int)aa, 1, 2);
}

float calcAOQuality(float3 p, float3 n, int sampleCount)
{
    if (sampleCount <= 0) return 1.0;
    float occ = 0.0;
    float sca = 1.0;
    [loop]
    for (int i = 1; i <= 5; i++)
    {
        if (i > sampleCount) break;
        float h = 0.02 + 0.06 * (float)i;
        occ += (h - sceneMap(p + n * h).x) * sca;
        sca *= 0.74;
    }
    return saturate(1.0 - 2.1 * occ);
}

float softShadowQuality(float3 ro, float3 rd, float k, float maxT, int stepCount)
{
    if (stepCount <= 0) return 1.0;
    float res = 1.0;
    float t = 0.02;
    [loop]
    for (int i = 0; i < 48; i++)
    {
        if (i >= stepCount) break;
        float h = sceneMap(ro + rd * t).x;
        if (h < 0.0004) return 0.0;
        res = min(res, k * h / t);
        t += clamp(h, 0.01, 0.25);
        if (t > maxT) break;
    }
    return saturate(res);
}

float marchQuality(float3 ro, float3 rd, out float outMat)
{
    outMat = -1.0;
    float t = 0.0;
    int maxSteps = qualityMarchSteps();
    float maxT = qualityMarchDistance();
    float hitEpsilon = qualitySurfaceEpsilon();
    float stepScale = qualityStepScale();
    [loop]
    for (int i = 0; i < 160; i++)
    {
        if (i >= maxSteps) break;
        float2 h = sceneMap(ro + rd * t);
        if (h.x < hitEpsilon * t + hitEpsilon * (2.0 / 7.0))
        {
            outMat = h.y;
            return t;
        }
        t += h.x * stepScale;
        if (t > maxT) break;
    }
    return -1.0;
}

float3 normalQuality(float3 p)
{
    float e = qualityNormalEpsilon();
    float2 k = float2(1.0, -1.0);
    return normalize(
        k.xyy * sceneMap(p + k.xyy * e).x +
        k.yyx * sceneMap(p + k.yyx * e).x +
        k.yxy * sceneMap(p + k.yxy * e).x +
        k.xxx * sceneMap(p + k.xxx * e).x);
}

// ---- instance helpers --------------------------------------------------------
float3 partLocal(BlobPart d, float3 p, out float minsc, out float maxsc)
{
    float3 q = p - float3(d.pos_xy.x, d.pos_xy.y, d.pos_z);
    q = sd_rotY(q, -d.yaw); q = sd_rotX(q, -d.tilt); q = sd_rotZ(q, -d.roll);
    float3 sc = float3(d.sc_xy.x, d.sc_xy.y, d.sc_z);
    minsc = min(sc.x, min(sc.y, sc.z)); maxsc = max(sc.x, max(sc.y, sc.z));
    return q / sc;
}

// ---- the blended mass (contract for sdf_shading.hlsli) -----------------------
float2 sceneMap(float3 p)
{
    float3 pw = domainDistort(p);
    float d = 1e9;
    uint c0 = min(min((uint)_Data0_Count, 128u), qualityPartLimit());
    [loop]
    for (uint i = 0u; i < 128u; i++)
    {
        if (i >= c0) break;
        BlobPart b = _Data0[i];
        if (b.active < 0.5) break;
        float3 cen = float3(b.pos_xy.x, b.pos_xy.y, b.pos_z);
        float maxsc = max(b.sc_xy.x, max(b.sc_xy.y, b.sc_z));
        float approx = length(pw - cen) - BLOB_BOUND_R * maxsc;   // conservative bound
        if (approx > blend_k + 0.08) { d = min(d, approx); continue; }
        float minsc, msc; float3 q = partLocal(b, pw, minsc, msc);
        float real = blob_sdf(q, (int)b.kind) * minsc;
        d = op_smin(d, real, blend_k);
    }
    return float2(d * distortLip(), 0.0);
}

// nearest part's surface colour + material, once per hit pixel
void shadeSample(float3 pos, out float3 albedo, out float refl, out float specMul)
{
    float3 pw = domainDistort(pos);
    float best = 1e9; albedo = float3(0.6, 0.6, 0.6); refl = 0.0; specMul = 1.0;
    uint c0 = min(min((uint)_Data0_Count, 128u), qualityPartLimit());
    [loop]
    for (uint i = 0u; i < 128u; i++)
    {
        if (i >= c0) break;
        BlobPart b = _Data0[i];
        if (b.active < 0.5) break;
        float3 cen = float3(b.pos_xy.x, b.pos_xy.y, b.pos_z);
        float maxsc = max(b.sc_xy.x, max(b.sc_xy.y, b.sc_z));
        if (length(pw - cen) - BLOB_BOUND_R * maxsc > best) continue;
        float minsc, msc; float3 q = partLocal(b, pw, minsc, msc);
        float real = blob_sdf(q, (int)b.kind) * minsc;
        if (real < best)
        {
            best = real;
            float rf; albedo = blob_albedo((int)b.mat, (int)b.colA, (int)b.colB, (int)b.grad, q, rf);
            refl = rf;
            specMul = ((int)b.mat == BM_MATTE) ? 0.15 : 1.0;
        }
    }
}

// ---- render one primary ray -> tonemapped colour + coverage ------------------
void renderRay(float3 ro, float3 rd, out float3 col, out float cov)
{
    float mat;
    int aoSamples = qualityAOSamples();
    int shadowSteps = qualityShadowSteps();
    float t = marchQuality(ro, rd, mat);
    if (t < 0.0) { col = 0.0; cov = 0.0; return; }

    float3 pos = ro + rd * t;
    float3 n = normalQuality(pos);
    float ao = calcAOQuality(pos, n, aoSamples);
    float3 sun = sdf_sunDir(sun_azimuth, sun_elevation);
    float sha = 1.0;
    if (shadows != 0 && shadowSteps > 0)
        sha = softShadowQuality(pos + n * 0.02, sun, 14.0, 18.0, shadowSteps);

    float3 albedo; float refl; float specMul;
    shadeSample(pos, albedo, refl, specMul);

    // surface ops (default off)
    if (facet_amt > 0.001) { float k = lerp(24.0, 3.0, saturate(facet_amt)); n = normalize(floor(n * k + 0.5) / k + 1e-4); }
    if (painterly_amt > 0.001) {
        float ps = painterly_scale;
        float3 rnd = float3(sd_hash21(pos.xy * ps) - 0.5, sd_hash21(pos.yz * ps + 3.1) - 0.5, sd_hash21(pos.zx * ps + 7.7) - 0.5);
        n = normalize(n + painterly_amt * 0.30 * rnd);
    }

    // glossy studio shade — tight highlight + fresnel env reflection
    float specAmt = gloss * 0.70 * specMul;
    float3 base = sdf_shade(albedo, n, rd, sun, sha, ao, specAmt, 52.0);
    base += albedo * str_envColor(n) * 0.10 * ao;                 // soft studio ambient (tinted by albedo)

    // reflection: chrome mirrors the studio; coloured gloss keeps its hue (env tinted toward albedo)
    float fres = pow(1.0 - saturate(dot(n, -rd)), 4.0);
    float3 rdir = reflect(rd, n);
    float3 env = (refl > 0.4) ? str_envColor(rdir) : lerp(str_envColor(rdir), albedo, 0.45);
    float k = saturate(refl_amt * refl * (0.15 + 0.85 * fres));
    float3 c = lerp(base, env, k);
    c += pow(saturate(dot(rdir, sun)), 120.0) * 0.9 * sha;        // sharp glossy glint

    // vividness: push saturation so the palette reads like ref #7 (not the muted studio wash)
    float l = dot(c, float3(0.299, 0.587, 0.114));
    c = max(lerp(float3(l, l, l), c, 1.32), 0.0);

    col = pow(saturate(c * exposure), 1.0 / 2.2);
    cov = 1.0;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    int N = qualityAA();
    float3 accCol = 0.0; float accA = 0.0;
    [loop]
    for (int sy = 0; sy < N; sy++)
    for (int sx = 0; sx < N; sx++)
    {
        float2 jit = (float2(sx, sy) + 0.5) / N - 0.5;
        float2 uv = ((float2)px + 0.5 + jit) / _Resolution.xy;
        float2 clip = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
        float4 nearW = mul(_InvViewProjMatrix, float4(clip, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(clip, 1.0, 1.0));
        nearW /= nearW.w;
        farW /= farW.w;
        float3 ro = _CameraPos;
        float3 rd = normalize(farW.xyz - nearW.xyz);
        float3 c; float cov;
        renderRay(ro, rd, c, cov);
        accCol += c * cov; accA += cov;             // premultiplied accumulation
    }
    float inv = 1.0 / (float)(N * N);
    OutputUAV[px] = float4(accCol * inv, accA * inv); // premultiplied RGBA coverage
}
