// VT_Volumes / march.hlsl — the sculpted masses.
//
// Ray-marches the limb chains as smooth-unioned round cones. Four materials share one scene:
// matte plaster clay, mirror chrome, translucent frost and glossy plastic. The chrome is the
// reason there is a procedural studio environment in here — it has to reflect THIS room
// (dark ceiling, bright horizon band, dark floor, one big key softbox) or it reads as
// noise-coloured metal instead of the liquid black-and-white of the reference.
//
// Culling: each mass publishes a bounding sphere in its group header, so a pixel pays 16
// sphere tests and only expands the handful of masses it can actually see.
#include "../_shared/vitrine.hlsli"
#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/sdf/sdf_noise.hlsli"

StructuredBuffer<PlanRec> Plan : register(t0);
StructuredBuffer<LimbRec> Limbs : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

// ---------------------------------------------------------------------------
// Scene
// ---------------------------------------------------------------------------

// Returns (distance, group index). Group -1 means "only a conservative bound was used".
float2 sceneMap(float3 p)
{
    float best = 1e9;
    float bestG = -1.0;

    [loop]
    for (uint g = 0u; g < LIMB_MASS_H; g++)
    {
        LimbRec h = Limbs[g];
        if (h.active < 0.5) continue;

        float db = length(p - h.pos) - h.radius;
        if (db >= best) continue;               // this whole mass is farther than what we have
        if (db > 0.25)                          // far enough that the bound is a safe step
        {
            best = db;
            continue;
        }

        uint first = (uint)max(h.parent, 0.0);
        uint count = (uint)max(h.group, 0.0);
        float d = 1e9;

        [loop]
        for (uint k = 0u; k < count && k < 96u; k++)
        {
            LimbRec n = Limbs[first + k];
            if (n.active < 0.5) continue;

            float dn;
            if (n.parent < 0.0)
            {
                dn = length(p - n.pos) - n.radius;
            }
            else
            {
                LimbRec pr = Limbs[(uint)n.parent];
                dn = sd_rcone(p, pr.pos, n.pos, pr.radius, n.radius);
            }
            d = (k == 0u) ? dn : op_smin(d, dn, blend);
        }

        if (d < best) { best = d; bestG = (float)g; }
    }
    return float2(best, bestG);
}

float3 calcNormal(float3 p, float eps)
{
    float2 e = float2(1.0, -1.0) * eps;
    return normalize(e.xyy * sceneMap(p + e.xyy).x + e.yyx * sceneMap(p + e.yyx).x +
                     e.yxy * sceneMap(p + e.yxy).x + e.xxx * sceneMap(p + e.xxx).x);
}

float calcAO(float3 p, float3 n)
{
    float occ = 0.0, sca = 1.0;
    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float hr = 0.012 + 0.09 * (float)i / 3.0;
        occ += (hr - sceneMap(p + n * hr).x) * sca;
        sca *= 0.72;
    }
    return saturate(1.0 - 2.6 * occ);
}

float softShadow(float3 ro, float3 rd, float k)
{
    float res = 1.0, t = 0.03;
    [loop]
    for (int i = 0; i < 20; i++)
    {
        float h = sceneMap(ro + rd * t).x;
        res = min(res, k * h / t);
        t += clamp(h, 0.02, 0.16);
        if (res < 0.02 || t > 1.6) break;
    }
    return saturate(res);
}

// ---------------------------------------------------------------------------
// The room, as seen by a mirror. Matches VT_Stage's palette on purpose.
// ---------------------------------------------------------------------------
float3 studioEnv(float3 rd)
{
    float3 c = lerp(env_mid.rgb, env_top.rgb, saturate(rd.y * 1.5 + 0.18));
    c += env_glow.rgb * exp(-abs(rd.y) * 6.5) * 0.85;                    // horizon band
    c = lerp(c, env_floor.rgb, saturate(-rd.y * 2.1));                   // dark ground

    float3 keyDir = normalize(float3(-0.42, 0.74, -0.52));
    c += float3(1.0, 0.99, 0.97) * pow(saturate(dot(rd, keyDir)), 20.0) * key_gain;

    float3 fillDir = normalize(float3(0.72, 0.18, -0.34));
    c += float3(0.60, 0.80, 1.0) * pow(saturate(dot(rd, fillDir)), 7.0) * fill_gain;
    return c;
}

// The chrome in the reference is black-and-white liquid metal, not blue metal — it is lit by a
// hard studio, not by the room. A crisp dark/light split plus one bright horizontal strip is
// what produces those long inky bands with a white edge.
float3 monoEnv(float3 rd)
{
    float split = smoothstep(-0.06, 0.22, rd.y);
    float3 c = lerp(float3(0.012, 0.012, 0.016), float3(0.93, 0.94, 0.98), split);
    c += float3(1.0, 1.0, 1.0) * exp(-pow((rd.y - 0.42) / 0.11, 2.0)) * 0.85;
    c += float3(1.0, 1.0, 1.0) * exp(-pow((rd.y + 0.30) / 0.06, 2.0)) * 0.35;
    c += float3(1.0, 0.99, 0.97) * pow(saturate(dot(rd, normalize(float3(-0.42, 0.74, -0.52)))), 26.0) * key_gain;
    return c;
}

// ---------------------------------------------------------------------------
// Materials
// ---------------------------------------------------------------------------
float3 shadeSurface(float3 p, float3 n, float3 rd, uint gidx, float ao)
{
    LimbRec h = Limbs[gidx];
    PlanRec pr = Plan[PLAN_MASS_0 + gidx];

    uint mat = (uint)h.material;
    float3 body = vt_body(pr.tone);

    float3 keyDir = normalize(float3(-0.42, 0.74, -0.52));
    float sh = lerp(1.0, softShadow(p, keyDir, 6.0), shadow_amt);

    // Plaster relief. Modifying the normal rather than the SDF keeps the march cheap and is
    // what actually reads at this scale — the reference's clay is finely pitted, not lumpy.
    int fin = (int)clay_finish;
    float finScale = 1.0, finAmp = 1.0;
    if (fin == 1)      { finScale = 0.50; finAmp = 0.55; }   // Wax   — broad soft undulation
    else if (fin == 2) { finScale = 2.60; finAmp = 1.65; }   // Sand  — coarse tooth
    else if (fin == 3) { finAmp = 0.0; }                     // Smooth — no relief at all

    if ((mat == MAT_CLAY || mat == MAT_GLOSS) && finAmp > 0.0)
    {
        float sc = 26.0 * grain_scale * finScale;
        float e = 0.006;
        float h0 = sd_triplanar_fbm(p, n, sc, 3);
        float hx = sd_triplanar_fbm(p + float3(e, 0, 0), n, sc, 3);
        float hy = sd_triplanar_fbm(p + float3(0, e, 0), n, sc, 3);
        float hz = sd_triplanar_fbm(p + float3(0, 0, e), n, sc, 3);
        float3 grad = float3(hx - h0, hy - h0, hz - h0) / e;
        n = normalize(n - (grad - n * dot(grad, n)) * grain * 0.010 * finAmp);
    }

    float ndl = dot(n, keyDir);
    float3 col;

    if (mat == MAT_CHROME)
    {
        float3 r = reflect(rd, n);
        float3 env = lerp(studioEnv(r), monoEnv(r), saturate(chrome_mono));
        float fres = pow(saturate(1.0 + dot(rd, n)), 4.0);
        // body tone tints the mirror; the near-black chrome in the reference is a dark tint,
        // not a different material
        col = env * lerp(body * 1.25, float3(1, 1, 1), 0.55 + 0.45 * fres);
        col *= lerp(0.55, 1.0, ao);
        col += float3(1, 1, 1) * pow(saturate(ndl), 90.0) * 1.4 * sh;
    }
    else if (mat == MAT_FROST)
    {
        // Cheap translucency: wrap lighting for the soft interior, a strong fresnel rim for the
        // edge glow, and AO standing in for thickness so the deep folds go milky.
        // Thin where the surface faces us, milky where it folds away: AO stands in for optical
        // thickness. The reference's blob is clearly see-through at its edges and dense in its
        // creases, which is the opposite of a marshmallow.
        float wrap = saturate((ndl + 0.75) / 1.75);
        float fres = pow(saturate(1.0 + dot(rd, n)), 2.0);
        float3 deep = body * 0.34;
        col = lerp(deep, body * 1.05, wrap * lerp(0.55, 1.0, sh));
        col *= lerp(0.52, 1.10, ao);                       // creases go dense and cool
        col += body * fres * frost_rim;                    // lit edge
        col += studioEnv(reflect(rd, n)) * 0.30 * fres;    // glassy edge reflection
        col += float3(0.86, 0.90, 1.0) * pow(saturate(ndl), 40.0) * 0.75;
    }
    else if (mat == MAT_GLOSS)
    {
        float3 hv = normalize(keyDir - rd);
        float spec = pow(saturate(dot(n, hv)), 64.0);
        col = body * (0.28 + 0.85 * saturate(ndl) * sh);
        col += studioEnv(reflect(rd, n)) * 0.13 * pow(saturate(1.0 + dot(rd, n)), 3.0);
        col += float3(1, 1, 1) * spec * 1.5 * sh;
        col *= lerp(0.55, 1.0, ao);
    }
    else // MAT_CLAY — the finish enum decides how the light sits in the surface
    {
        // Wax carries light further round the form; sand cuts off hard; plaster is between.
        float wrapK = (fin == 1) ? 0.85 : ((fin == 2) ? 0.18 : 0.42);
        float wrap = saturate((ndl + wrapK) / (1.0 + wrapK));
        col = body * (0.20 + 0.92 * wrap * lerp(0.35, 1.0, sh));

        // bounce from the bright cyan floor/horizon, which is what keeps the reference's clay
        // from going flat and dead on its underside
        col += body * env_glow.rgb * saturate(-n.y * 0.8 + 0.2) * bounce * 0.5;

        float3 hv = normalize(keyDir - rd);
        float sheenPow = (fin == 2) ? 6.0 : ((fin == 3) ? 40.0 : 18.0);
        float sheenAmt = (fin == 2) ? 0.03 : ((fin == 3) ? 0.28 : 0.10);
        col += float3(1, 1, 1) * pow(saturate(dot(n, hv)), sheenPow) * sheenAmt * sh;

        if (fin == 1)   // wax also glows slightly through thin edges
            col += body * pow(saturate(1.0 + dot(rd, n)), 3.0) * 0.22;

        col *= lerp((fin == 2) ? 0.30 : 0.42, 1.0, ao);
    }

    return col;
}

// ---------------------------------------------------------------------------
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float3 acc = float3(0, 0, 0);
    float cov = 0.0;
    int aa = clamp((int)aa_samples, 1, 3);

    for (int sy = 0; sy < aa; sy++)
    for (int sx = 0; sx < aa; sx++)
    {
        float2 jit = (float2((float)sx, (float)sy) + 0.5) / (float)aa;
        float2 screenUV = ((float2)pixel + jit) / _Resolution.xy;
        float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

        // internal camera, DirectX Y flip — the same matrices every pass here uses
        float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
        float4 farW = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
        nearW /= nearW.w;
        farW /= farW.w;
        float3 ro = _CameraPos;
        float3 rd = normalize(farW.xyz - nearW.xyz);

        float t = 0.02;
        float g = -1.0;
        int steps = clamp((int)march_steps, 24, 256);
        float eps = max(surface_eps, 0.00005);
        bool hit = false;

        [loop]
        for (int i = 0; i < steps; i++)
        {
            float3 p = ro + rd * t;
            float2 m = sceneMap(p);
            if (m.x < eps * t * 40.0 + eps && m.y >= 0.0) { g = m.y; hit = true; break; }
            t += max(m.x * step_scale, eps * 2.0);
            if (t > 6.0) break;
        }

        if (hit && g >= 0.0)
        {
            float3 p = ro + rd * t;
            float3 n = calcNormal(p, max(normal_eps, 0.0002));
            float ao = lerp(1.0, calcAO(p, n), ao_amt);
            acc += shadeSurface(p, n, rd, (uint)g, ao);
            cov += 1.0;
        }
    }

    float inv = 1.0 / (float)(aa * aa);
    OutputUAV[pixel] = float4(acc * inv * exposure, cov * inv);
}
