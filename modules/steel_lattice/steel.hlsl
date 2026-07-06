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
#include "../_shared/sdf/sdf_shading.hlsli"

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

// ---- the infinite lattice (contract for sdf_shading.hlsli) ------------------
float2 sceneMap(float3 p)
{
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
    return float2(d, 1.0);
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
        if (h < 0.0006 * t + 0.0004) return t;
        t += h * 0.82;
        if (t > maxT) break;
    }
    return -1.0;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = (uv * 2.0 - 1.0) * float2(_Resolution.x / _Resolution.y, -1.0);

    float3 ro; float3 rd;
    if (cam_mode == 0)   // Fly
    {
        // canonical fly camera: unproject the near/far NDC points through the live
        // inverse view-projection so WASD + right-drag in the viewport actually steer.
        // NDC is Y-flipped for DX clip space (top = +1).
        float2 ndcv = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
        float4 nearW = mul(_InvViewProjMatrix, float4(ndcv, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndcv, 1.0, 1.0));
        nearW /= nearW.w; farW /= farW.w;
        ro = _CameraPos;
        rd = normalize(farW.xyz - nearW.xyz);
    }
    else
    {
        float az = cam_orbit + rotate_speed * _Time * 30.0;
        sdf_orbitRay(az, cam_elevation, cam_distance,
                     float3(0.0, cam_target_y, 0.0), ndc, cam_focal, ro, rd);
    }

    g_camPos = ro;   // feed sceneMap's distance LOD (correct in both camera modes)

    float3 sun = sdf_sunDir(sun_azimuth, sun_elevation);
    float3 bg = bg_color;

    float t = march(ro, rd, march_dist, 160);

    float3 col = bg;
    if (t >= 0.0)   // march returns -1 for a true miss; t==0 (camera on/in surface) is a hit
    {
        float3 pos = ro + rd * t;
        float3 n = sdf_calcNormal(pos);
        float ao = sdf_calcAO(pos, n);

        float sha = 1.0;
        if (shadows != 0)
            sha = sdf_softShadow(pos + n * 0.02, sun, 8.0, 14.0);

        col = sdf_shade(steel_color, n, rd, sun, sha, ao, spec_amt, 28.0);

        // recede into darkness with distance — the reference falls off to black
        float fog = 1.0 - exp(-fog_density * 0.06 * max(t, 0.0));
        col = lerp(col, bg, fog);
    }

    // optional desaturate toward the black-and-white reference look
    float luma = dot(col, float3(0.299, 0.587, 0.114));
    col = lerp(col, luma.xxx, desaturate);

    col = pow(saturate(col * exposure), 1.0 / 2.2);
    OutputUAV[pixel] = float4(col, 1.0);
}
