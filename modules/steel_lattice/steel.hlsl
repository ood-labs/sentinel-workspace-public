// steel_lattice — an INFINITE industrial structural lattice built with pure domain
// repetition. No mesh, no placement buffer, no bounds: the whole space frame is one
// signed distance function that tiles forever in X, Y and Z.
//
// Three infinite families, unioned:
//   columns  : square box-section posts at every XZ grid point, infinite along Y
//   beams-X  : horizontal bars running along X, at every floor height (Y) and Z line
//   beams-Z  : horizontal bars running along Z, at every floor height (Y) and X line
//
// Formwork panels are carved as REAL recessed grooves into the surface (see
// carveGrooves) — actual geometry that changes the silhouette and self-shadows.

#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/sdf/sdf_noise.hlsli"
#include "../_shared/sdf/sdf_shading.hlsli"
#include "distortion.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// world-space camera position for distance LOD inside sceneMap. Set in main() to the
// active ray origin (works for BOTH fly and orbit — _CameraPos alone is wrong in orbit).
static float3 g_camPos = float3(0, 0, 0);

// 2D box distance (exact). Used for the cross-section of an infinite extrusion.
float box2(float2 p, float2 b)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// rounded 2D box: r rounds the member corners (chamfered concrete columns/beams)
float box2round(float2 p, float2 b, float r)
{
    r = min(r, min(b.x, b.y) * 0.9);
    return box2(p, b - r) - r;
}

// signed 1D repetition: fold coordinate into its nearest cell of size c
float rep1(float x, float c) { return x - c * round(x / c); }

// Carve ONE set of recessed grooves. gdist = distance to the nearest groove plane of
// this set; half_w = groove half-width; depth = how deep. The cutter = (thin slot) ∩
// (near-surface slab that straddles the surface via +eps), subtracted from the solid.
// All max/min of exact SDFs -> stays 1-Lipschitz, no extra overshoot.
float carveOne(float d, float gdist, float half_w, float depth)
{
    if (depth <= 0.0006) return d;
    const float eps = 0.02;                       // reach a hair outside so the cut bites
    float grooveLine = gdist - half_w;            // < 0 inside a slot
    float shell  = max(d - eps, -d - depth);      // slab straddling the surface
    float cutter = max(grooveLine, shell);
    return max(d, -cutter);
}

// Carve REAL recessed formwork grooves on a world-aligned panel grid. Horizontal bands
// (Y planes) and vertical flutes (X/Z planes) have independent width + depth so the
// floor-lines and the column fluting can be sculpted separately.
float carveGrooves(float d, float3 p)
{
    if (panels_on == 0) return d;

    // fade groove depth with camera distance so far cells stay clean boxes (no alias)
    float lod = saturate(1.0 - (length(p - g_camPos) - 7.0) / 24.0);
    if (lod <= 0.0) return d;

    // distance to nearest groove plane per axis (offset slides the grid to align seams)
    float gy = abs(frac((p.y - panel_off_y) / panel_h + 0.5) - 0.5) * panel_h;
    float gx = abs(frac((p.x - panel_off_x) / panel_w + 0.5) - 0.5) * panel_w;
    float gz = abs(frac((p.z - panel_off_z) / panel_w + 0.5) - 0.5) * panel_w;

    d = carveOne(d, gy, band_width,  band_depth  * lod);   // horizontal floor bands
    d = carveOne(d, gx, flute_width, flute_depth * lod);   // vertical flutes (X planes)
    d = carveOne(d, gz, flute_width, flute_depth * lod);   // vertical flutes (Z planes)
    return d;
}

// Add REAL junction hardware at each beam<->column node: a connection collar wrapping
// the joint plus bolt heads on its faces. Guard-banded so it only evaluates near a node
// (not across all space). Unioned into the field -> real geometry that self-shadows.
float addHardware(float d, float3 p)
{
    if (junctions_on == 0) return d;

    // nearest node = (XZ grid intersection, Y floor level) — where beams meet a column
    float3 node = float3(round(p.x / cell) * cell,
                         round(p.y / floor_h) * floor_h,
                         round(p.z / cell) * cell);
    float3 q = p - node;

    float cx = col_thick + collar_out;                 // collar half-width in X/Z
    float reach = max(cx + bolt_radius, collar_h) + 0.15;
    if (max(abs(q.x), max(abs(q.y), abs(q.z))) > reach) return d;   // guard-band cull

    // connection collar wrapping the joint (rounded box, proud of the column)
    float hw = sd_rbox(q, float3(cx, collar_h, cx), min(collar_round, cx * 0.9));

    // bolt heads: hemispheres gridded on the four vertical collar faces, clipped to
    // the collar rectangle (exact intersection -> Lipschitz-safe, never a hard window)
    if (bolts_on != 0 && bolt_radius > 0.001)
    {
        float3 bx = float3(abs(q.x) - cx, rep1(q.y, bolt_pitch), rep1(q.z, bolt_pitch));
        float boltX = max(sd_sphere(bx, bolt_radius), sd_box(q, float3(cx + bolt_radius, collar_h, cx)));

        float3 bz = float3(rep1(q.x, bolt_pitch), rep1(q.y, bolt_pitch), abs(q.z) - cx);
        float boltZ = max(sd_sphere(bz, bolt_radius), sd_box(q, float3(cx, collar_h, cx + bolt_radius)));

        hw = min(hw, min(boltX, boltZ));
    }

    return min(d, hw);
}

// ---- the infinite lattice (contract for sdf_shading.hlsli) ------------------
float2 sceneMap(float3 p)
{
    p = latticeDomainDistort(p);

    // vertical columns: infinite in Y, on the XZ grid
    float2 pc = float2(rep1(p.x, cell), rep1(p.z, cell));
    float dCol = box2round(pc, col_thick.xx, member_round);

    // beams along X: infinite in X, folded in Y (floors) and Z (grid lines)
    float2 pbx = float2(rep1(p.y, floor_h), rep1(p.z, cell));
    float dBX = box2round(pbx, float2(beam_h, beam_w), member_round);

    // beams along Z: infinite in Z, folded in Y (floors) and X (grid lines)
    float2 pbz = float2(rep1(p.y, floor_h), rep1(p.x, cell));
    float dBZ = box2round(pbz, float2(beam_h, beam_w), member_round);

    float d = min(dCol, min(dBX, dBZ));
    d = carveGrooves(d, p);
    d = addHardware(d, p);
    return float2(d * latticeDistortLip(), 1.0);
}

// relaxed sphere-trace: domain repetition can slightly over-report distance at
// glancing angles, so under-step to avoid punching through thin members.
float march(float3 ro, float3 rd, float maxT, int maxSteps)
{
    float t = 0.0;
    for (int i = 0; i < 256; i++)
    {
        if (i >= maxSteps) break;
        float h = sceneMap(ro + rd * t).x;
        if (h < surface_epsilon * t + surface_epsilon * (2.0 / 3.0)) return t;
        t += h * step_scale;
        if (t > maxT) break;
    }
    return -1.0;
}

// Parameterized tetrahedral normal so surface smoothness can be tuned independently
// from the shared SDF defaults. Smaller epsilon preserves finer surface detail.
float3 latticeNormal(float3 p)
{
    float e = normal_epsilon;
    float2 k = float2(1.0, -1.0);
    return normalize(
        k.xyy * sceneMap(p + k.xyy * e).x +
        k.yyx * sceneMap(p + k.yyx * e).x +
        k.yxy * sceneMap(p + k.yxy * e).x +
        k.xxx * sceneMap(p + k.xxx * e).x);
}

// Full per-ray shade: camera ray -> march -> weathered concrete + headlamp -> fade to
// black. Returns linear HDR. Called once per sub-sample so supersampling averages both
// geometry edges AND shading noise (real SSAA).
float3 shadeRay(float2 uv)
{
    float2 ndc = (uv * 2.0 - 1.0) * float2(_Resolution.x / _Resolution.y, -1.0);

    float3 ro; float3 rd;
    if (cam_mode == 0)   // Fly: unproject through the live inverse view-projection
    {
        float2 ndcv = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
        float4 nearW = mul(_InvViewProjMatrix, float4(ndcv, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndcv, 1.0, 1.0));
        nearW /= nearW.w; farW /= farW.w;
        ro = _CameraPos;
        rd = normalize(farW.xyz - nearW.xyz);
    }
    else                 // Orbit
    {
        float az = cam_orbit + rotate_speed * _Time * 30.0;
        sdf_orbitRay(az, cam_elevation, cam_distance,
                     float3(0.0, cam_target_y, 0.0), ndc, cam_focal, ro, rd);
    }

    g_camPos = latticeDomainDistort(ro); // keep distance LOD in the deformed domain

    float t = march(ro, rd, march_dist, clamp((int)march_steps, 32, 256));
    if (t < 0.0) return float3(0.0, 0.0, 0.0);   // miss -> fade-to-black background

    float3 pos = ro + rd * t;
    float3 n = latticeNormal(pos);
    float ao = sdf_calcAO(pos, n);

    // high-frequency surface detail fades with distance to kill shimmer (SSAA does the rest)
    float detailLod = saturate(1.0 - (t - 8.0) / 26.0);

    // ---- weathered concrete albedo: layered noise, coarse -> fine (heavy decay) ----
    float ns = noise_scale;
    float3 albedo = steel_color;

    // macro tone: large patchy staining (triplanar so it wraps faces)
    float macro = sd_triplanar_fbm(pos, n, ns * 0.5, 4);
    albedo *= lerp(1.0 - 0.55 * grime_amount, 1.0 + 0.22 * grime_amount, macro);

    // spalled blotches: darker exposed aggregate (low-freq, always on)
    float spall = sd_fbm3(pos * ns * 0.5 + 13.7, 3);
    albedo = lerp(albedo, albedo * 0.4, spall_amount * smoothstep(0.5, 0.72, spall));

    // ---- fine detail layers (near-field only: skip far to save cost + avoid alias) ----
    if (detailLod > 0.004)
    {
        // meso mottle (medium frequency)
        float meso = sd_fbm3(pos * ns * 2.3 + 5.1, 5);
        albedo *= lerp(1.0, 0.72 + 0.55 * meso, grime_amount * detailLod);
        // fine grain / pitting (concrete pores, high frequency)
        float micro = sd_fbm3(pos * ns * 7.0, 3);
        albedo *= 1.0 - detail_amount * detailLod * (micro - 0.5) * 0.9;
        // vertical drip-streaks: domain-warped fbm, sharpened, only on vertical faces
        float vface = 1.0 - abs(n.y);
        float streak = sd_fbm3_warp(float3(pos.x, pos.y * 0.2, pos.z) * ns * 1.6, 4, 0.6);
        streak = pow(saturate(streak), lerp(1.0, 5.0, streak_sharp));
        albedo *= 1.0 - streak_amount * detailLod * vface * streak;
        // cracks / veins: ridged turbulence, thin dark lines
        float cr = sd_ridged3(pos * ns * 1.4, 4);
        albedo = lerp(albedo, albedo * 0.3, crack_amount * detailLod * smoothstep(0.68, 0.92, cr));
    }

    // grime settles into the AO recesses (always on)
    albedo *= lerp(1.0, 0.55, saturate((1.0 - ao) * grime_amount * 1.5));
    // worn bright edges (geometry-driven arris highlight)
    float3 an = abs(n);
    float mx = max(an.x, max(an.y, an.z));
    float sm = an.x + an.y + an.z - mx - min(an.x, min(an.y, an.z));
    float edge = smoothstep(0.15, 0.5, sm / max(mx, 1e-3));
    albedo = lerp(albedo, albedo * 1.7 + 0.06, edge * edge_wear * detailLod);

    // ---- camera headlamp lighting (everything fades to black) ----
    // the lamp lives at the ACTIVE ray origin ro (correct for fly AND orbit). camDist == t.
    float3 L = normalize(ro - pos);
    float diff = max(dot(n, L), 0.0);
    float atten = exp(-spot_falloff * t);              // distance falloff
    float cone  = exp(-spot_cone * dot(ndc, ndc));     // torch beam: brighter center
    float sha = 1.0;
    if (shadows != 0)
        sha = sdf_softShadow(pos + n * 0.02, L, 9.0, min(t, 12.0));
    float key  = spot_intensity * diff * atten * cone * sha;
    float spec = pow(max(dot(n, L), 0.0), 40.0) * spec_amt * atten * cone;
    float3 sunDir = sdf_sunDir(sun_azimuth, sun_elevation);
    float fill = sun_fill * max(dot(n, sunDir), 0.0);

    float3 col = albedo * (ambient * ao + key + fill) + spec;
    col *= exp(-fog_density * 0.06 * max(t, 0.0));      // recede into pure black
    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    // supersample: cast an ss x ss grid of jittered rays per pixel and average
    int ss = clamp((int)aa_samples, 1, 8);
    float3 acc = float3(0.0, 0.0, 0.0);
    [loop]
    for (int sy = 0; sy < 8; sy++)
    {
        if (sy >= ss) break;
        [loop]
        for (int sx = 0; sx < 8; sx++)
        {
            if (sx >= ss) break;
            float2 sub = (float2(sx, sy) + 0.5) / (float)ss;
            acc += shadeRay(((float2)pixel + sub) / _Resolution.xy);
        }
    }
    acc /= (float)(ss * ss);

    // linear HDR out — bloom + full B&W grade happen downstream in the mono_post node
    OutputUAV[pixel] = float4(acc, 1.0);
}
