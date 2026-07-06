// sdf_scene_render — raymarched 3D instancer: consumes a PNode placement stream
// (data:0) and renders real SDF geometry (chairs, tables, towers, trees, ...)
// standing on a ground plane, with sun shadows, AO, and fog. The 3D sibling of
// pl_render: pl_grid/pl_spawn/pl_path chains become rooms, plazas, and cities.
//   canvas mapping: PNode.pos.x -> world X, PNode.pos.y -> world Z, ground y=0
//   kind -> obj_sdf vocabulary (see _shared/sdf/sdf_objects.hlsli)

#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/sdf/sdf_objects.hlsli"
#include "../_shared/sdf/sdf_shading.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

#define MAX_LIST 24
static int  g_list[MAX_LIST];
static int  g_count = 0;

// ---- instance mapping (must match between shortlist + sceneMap) -------------
void instXform(uint i, out float3 c, out float s, out float yaw, out int kind, out float sd)
{
    PNode n = _Data0[i];
    c = float3(n.pos.x * world_scale, 0.0, n.pos.y * world_scale);
    sd = n.seed;

    float hs = sd_hash11(n.seed * 2.17 + 1.3);
    s = scale_base;
    if (scale_mode == 1) s *= lerp(1.0 - scale_var, 1.0, saturate(n.weight));
    else if (scale_mode == 2) s *= lerp(1.0 - scale_var, 1.0, saturate(n.depth));
    else if (scale_mode == 3) s *= lerp(1.0 - scale_var, 1.0 + scale_var, hs);
    s = max(s, 0.02);

    if (rot_mode == 0) yaw = atan2(n.dir.y, n.dir.x) + fixed_rot;
    else if (rot_mode == 1) yaw = fixed_rot;
    else yaw = (sd_hash11(n.seed * 3.71 + 0.7) * 2.0 - 1.0) * 3.14159 + fixed_rot;

    int kset[4] = { kind0, kind1, kind2, kind3 };
    int setN = max(min(set_size, 4), 1);
    if (kind_mode == 0) kind = (int)floor(n.kind + 0.5);
    else if (kind_mode == 1) kind = fixed_kind;
    else if (kind_mode == 2) kind = kset[(int)i % setN];
    else kind = kset[(int)(sd_hash11(n.seed * 6.11 + 2.9) * 3.99) % setN];
    kind = clamp(kind, 0, OBJ_KIND_COUNT - 1);
}

void buildShortlist(float3 ro, float3 rd)
{
    g_count = 0;
    uint cnt = min((uint)_Data0_Count, (uint)render_count);
    [loop]
    for (uint i = 0u; i < 256u; i++)
    {
        if (i >= cnt) break;
        if (_Data0[i].active < 0.5) continue;
        float3 c; float s; float yaw; int kind; float sd;
        instXform(i, c, s, yaw, kind, sd);
        float3 cs = c + OBJ_BOUND_C * s;
        float r = OBJ_BOUND_R * s;
        float3 oc = cs - ro;
        float tca = dot(oc, rd);
        if (tca < -r) continue;
        float d2 = dot(oc, oc) - tca * tca;
        if (d2 > r * r) continue;
        if (g_count < MAX_LIST) { g_list[g_count] = (int)i; g_count++; }
    }
}

// scene = ground plane + shortlisted instances (contract for sdf_shading.hlsli)
float2 sceneMap(float3 p)
{
    float2 res = float2(p.y, MAT_GROUND);
    [loop]
    for (int j = 0; j < MAX_LIST; j++)
    {
        if (j >= g_count) break;
        float3 c; float s; float yaw; int kind; float sd;
        instXform((uint)g_list[j], c, s, yaw, kind, sd);
        float3 q = sd_rotY(p - c, -yaw) / s;
        float2 o = obj_sdf(q, kind, sd);
        o.x *= s;
        o.y += 0.45 * sd_hash11(sd * 11.3 + 4.2);  // per-instance tint in frac
        res = op_matmin(res, o);
    }
    return res;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = (uv * 2.0 - 1.0) * float2(_Resolution.x / _Resolution.y, -1.0);

    float3 ro; float3 rd;
    if (use_fly_cam != 0)
    {
        ro = _CameraPos;
        rd = _RayDirection(uv);
    }
    else
    {
        float az = cam_orbit + rotate_speed * _Time * 30.0;
        sdf_orbitRay(az, cam_elevation, cam_distance,
                     float3(0.0, cam_target_y, 0.0), ndc, 1.8, ro, rd);
    }

    float3 sun = sdf_sunDir(sun_azimuth, sun_elevation);
    float3 bg = lerp(float3(0.13, 0.14, 0.17), float3(0.030, 0.032, 0.045), uv.y);
    bg += pow(saturate(dot(rd, sun)), 24.0) * float3(0.25, 0.20, 0.12);

    buildShortlist(ro, rd);
    float matId;
    float t = sdf_march(ro, rd, 60.0, 140, matId);

    float3 col = bg;
    if (t > 0.0)
    {
        float3 pos = ro + rd * t;
        float3 n = sdf_calcNormal(pos);
        float ao = sdf_calcAO(pos, n);

        int m = (int)floor(matId + 0.001);
        float tintH = frac(matId) / 0.45;

        float sha = 1.0;
        if (shadows != 0 && m != 4)
        {
            buildShortlist(pos + n * 0.02, sun);   // shadow-ray shortlist
            sha = sdf_softShadow(pos + n * 0.02, sun, 9.0, 12.0);
        }

        float3 albedo;
        float specAmt; float specPow;
        if (m == 0)
        {
            albedo = ground_color;
            if (grid_lines != 0)
            {
                float2 gp = abs(frac(pos.xz / 0.5) - 0.5) * 2.0;
                float ln = 1.0 - smoothstep(0.0, 0.10, min(gp.x, gp.y));
                albedo *= 1.0 - ln * 0.35;
            }
            specAmt = 0.06; specPow = 12.0;
        }
        else if (m == 1) { albedo = base_color;               specAmt = 0.30; specPow = 24.0; }
        else if (m == 2) { albedo = accent_color;             specAmt = 0.18; specPow = 10.0; }
        else if (m == 3) { albedo = float3(0.33, 0.34, 0.38); specAmt = 0.90; specPow = 48.0; }
        else if (m == 5) { albedo = float3(0.16, 0.38, 0.15); specAmt = 0.10; specPow = 8.0;  }
        else             { albedo = emissive_color;           specAmt = 0.0;  specPow = 8.0;  }

        if (m >= 1 && m != 4) albedo *= 0.82 + 0.36 * tintH;

        if (m == 4)
            col = emissive_color * (1.8 + 0.6 * sin(_Time * 2.0)) * (0.7 + 0.3 * ao);
        else
            col = sdf_shade(albedo, n, rd, sun, sha, ao, specAmt, specPow);

        float fog = 1.0 - exp(-fog_density * 0.10 * max(t - 2.0, 0.0));
        col = lerp(col, bg, fog);
    }

    col = pow(saturate(col), 0.92);
    OutputUAV[pixel] = float4(col, 1.0);
}
