// sdf_industrial_scene_render - one-depth-domain raymarched industrial interior.
// Inputs: data:0 StructPart architecture, data:1 GreeblePart surface detail.

#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/sdf/sdf_shading.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct StructPart {
    float3 center; float3 axis; float3 up; float3 half_extents;
    float length; float radius; float kind; float material;
    float seed; float group; float active; float spare;
};

struct GreeblePart {
    float3 anchor; float3 normal; float3 tangent; float2 uv; float3 size;
    float kind; float material; float parent_id; float seed; float active; float spare;
};

float3 safeNorm(float3 v, float3 fb)
{
    float l = length(v);
    return l > 1e-4 ? v / l : fb;
}

float h11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float n31(float3 p)
{
    return h11(dot(p, float3(19.17, 47.31, 73.11)));
}

void partBasis(StructPart sp, out float3 rightV, out float3 upV, out float3 fwdV)
{
    fwdV = safeNorm(sp.axis, float3(0, 0, 1));
    upV = safeNorm(sp.up - fwdV * dot(sp.up, fwdV), float3(0, 1, 0));
    rightV = safeNorm(cross(upV, fwdV), float3(1, 0, 0));
}

float3 toPartLocal(StructPart sp, float3 p)
{
    float3 r, u, f;
    partBasis(sp, r, u, f);
    float3 d = p - sp.center;
    return float3(dot(d, r), dot(d, u), dot(d, f));
}

float sd_cyl_z(float3 p, float radius, float halfLen)
{
    float2 d = abs(float2(length(p.xy), p.z)) - float2(radius, halfLen);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sd_capsule_z(float3 p, float halfLen, float radius)
{
    p.z -= clamp(p.z, -halfLen, halfLen);
    return length(p) - radius;
}

float2 matMin(float2 a, float d, float m)
{
    return (d < a.x) ? float2(d, m) : a;
}

float partSdf(StructPart sp, float3 p, out float matId)
{
    float3 q = toPartLocal(sp, p);
    float3 he = max(sp.half_extents, float3(0.005, 0.005, 0.005));
    int kind = (int)floor(sp.kind + 0.5);
    float edgeR = max(0.005, min(min(he.x, he.y), he.z) * 0.12);
    matId = sp.material;

    if (kind == 0)
    {
        float body = sd_rbox(q, he, edgeR);
        float bandSpacing = max(column_band_spacing, 0.25);
        float bandZ = abs(frac((q.z + he.z) / bandSpacing) - 0.5) * bandSpacing;
        float band = sd_rbox(float3(q.x, q.y, bandZ), float3(he.x * 1.16, he.y * 1.16, column_band_width), edgeR * 0.4);
        float sidePanel = sd_rbox(float3(q.x, q.y, q.z), float3(he.x * 1.04, he.y * 0.54, he.z * 0.72), edgeR * 0.45);
        float d = min(body, max(sidePanel, -body));
        d = min(d, band);
        return d;
    }
    if (kind == 1)
    {
        float flangeTop = sd_rbox(q - float3(0, he.y * 0.68, 0), float3(he.x, he.y * 0.24, he.z), edgeR);
        float flangeBot = sd_rbox(q + float3(0, he.y * 0.68, 0), float3(he.x, he.y * 0.24, he.z), edgeR);
        float web = sd_rbox(q, float3(he.x * web_thickness, he.y, he.z), edgeR * 0.6);
        return min(web, min(flangeTop, flangeBot));
    }
    if (kind == 2 || kind == 3 || kind == 11)
    {
        float d = sd_rbox(q, he, edgeR);
        if (kind == 11)
        {
            float cut = dot(q, safeNorm(float3(0.7, 0.35, 0.6), float3(1,0,0))) - he.z * 0.18;
            d = max(d, cut);
            matId = 3.0;
        }
        return d;
    }
    if (kind == 4)
    {
        float d = sd_rbox(q, he, edgeR * 0.5);
        if (grating_strength > 0.0)
        {
            float slot = abs(frac(q.x / max(grating_spacing, 0.05)) - 0.5) * max(grating_spacing, 0.05);
            float groove = sd_box(float3(slot, q.y - he.y * 0.85, q.z), float3(grating_spacing * 0.12, he.y * 0.25, he.z * 1.05));
            d = max(d, -groove * grating_strength);
        }
        return d;
    }
    if (kind == 6 || kind == 8)
    {
        matId = 3.0;
        return sd_cyl_z(q, max(he.x, he.y), he.z);
    }
    if (kind == 7)
    {
        matId = 3.0;
        float railA = sd_capsule_z(q - float3(-he.x, 0, 0), he.z, he.y);
        float railB = sd_capsule_z(q - float3( he.x, 0, 0), he.z, he.y);
        float spacing = max(ladder_rung_spacing, 0.08);
        float rz = (frac((q.z + he.z) / spacing) - 0.5) * spacing;
        float rung = sd_rbox(float3(q.x, q.y, rz), float3(he.x, he.y * 0.9, he.y * 0.55), he.y * 0.35);
        return min(min(railA, railB), rung);
    }
    if (kind == 9)
    {
        matId = 4.0;
        return sd_rbox(q, he, edgeR * 0.5);
    }
    if (kind == 10)
    {
        matId = 2.0;
        return sd_rbox(q, he, edgeR);
    }
    return sd_rbox(q, he, edgeR);
}

float3 toGreebleLocal(GreeblePart g, float3 p)
{
    float3 n = safeNorm(g.normal, float3(0,1,0));
    float3 t = safeNorm(g.tangent - n * dot(g.tangent, n), float3(1,0,0));
    float3 b = safeNorm(cross(n, t), float3(0,0,1));
    float3 d = p - g.anchor;
    return float3(dot(d, t), dot(d, b), dot(d, n));
}

float greebleSdf(GreeblePart g, float3 p, out float matId)
{
    float3 q = toGreebleLocal(g, p);
    float3 sz = max(g.size, float3(0.002, 0.002, 0.002));
    int kind = (int)floor(g.kind + 0.5);
    matId = g.material;

    if (kind == 0)
    {
        return sd_sphere(q - float3(0, 0, sz.z), sz.x);
    }
    if (kind == 2 || kind == 7 || kind == 14)
    {
        return sd_rbox(q - float3(0, 0, sz.z), sz, min(sz.x, sz.y) * 0.08);
    }
    if (kind == 4)
    {
        return sd_rbox(q - float3(0, 0, sz.z), float3(sz.x, sz.y, sz.z), sz.x * 0.4);
    }
    if (kind == 5)
    {
        float plate = sd_rbox(q - float3(0,0,sz.z * 0.6), sz, sz.z * 0.3);
        float slat = abs(frac((q.y + sz.y) / max(sz.y * 0.32, 0.01)) - 0.5) * max(sz.y * 0.32, 0.01);
        float cut = sd_box(float3(q.x, slat, q.z - sz.z * 1.2), float3(sz.x * 0.75, sz.y * 0.035, sz.z * 1.6));
        return max(plate, -cut);
    }
    if (kind == 6)
    {
        float band = sd_rbox(q - float3(0,0,sz.z), float3(sz.x, sz.y, sz.z), sz.z * 0.4);
        float hole = sd_cyl_z(float3(q.x, q.z - sz.z, q.y), sz.x * 0.52, sz.y * 1.2);
        return max(band, -hole);
    }
    if (kind == 8)
    {
        return sd_capsule_z(float3(q.x, q.z, q.y), sz.y, sz.x);
    }
    if (kind == 9)
    {
        float wave = sin(q.y * 80.0 + g.seed) * sz.x * 0.2;
        return sd_capsule_z(float3(q.x + wave, q.z, q.y), sz.y, sz.x);
    }
    if (kind == 10)
    {
        matId = 3.0;
        return sd_rbox(q - float3(0,0,sz.z * 0.5), float3(sz.x, sz.y, sz.z), sz.z * 0.2);
    }
    return sd_rbox(q - float3(0,0,sz.z), sz, sz.z * 0.25);
}

float2 sceneMap(float3 p)
{
    float2 res = float2(1e4, 2.0);
    if (enable_ground != 0)
    {
        res = float2(p.y + ground_drop, 2.0);
    }

    uint partCnt = min((uint)_Data0_Count, (uint)max_struct_parts);
    [loop]
    for (uint i = 0u; i < 1024u; i++)
    {
        if (i >= partCnt) break;
        StructPart sp = _Data0[i];
        if (sp.active < 0.5) continue;
        float bound = length(p - sp.center) - sp.radius * 1.85 - 0.25;
        if (bound < detail_guard)
        {
            float m;
            float d = partSdf(sp, p, m);
            res = matMin(res, d, m + h11(sp.seed) * 0.21);
        }
        else
        {
            res.x = min(res.x, bound);
        }
    }

    if (enable_greebles != 0)
    {
        uint gCnt = min((uint)_Data1_Count, (uint)max_greebles);
        [loop]
        for (uint j = 0u; j < 4096u; j++)
        {
            if (j >= gCnt) break;
            GreeblePart g = _Data1[j];
            if (g.active < 0.5) continue;
            float br = max(max(g.size.x, g.size.y), g.size.z) * 1.8 + 0.035;
            float bound = length(p - g.anchor) - br;
            if (bound < greeble_distance)
            {
                float gm;
                float d = greebleSdf(g, p, gm);
                res = matMin(res, d, gm + h11(g.seed) * 0.18);
            }
            else
            {
                res.x = min(res.x, bound);
            }
        }
    }

    return res;
}

void makeCamera(float2 uv, float2 ndc, out float3 ro, out float3 rd)
{
    float2 clip = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nearW = mul(_InvViewProjMatrix, float4(clip, 0.0, 1.0));
    float4 farW = mul(_InvViewProjMatrix, float4(clip, 1.0, 1.0));
    nearW /= max(abs(nearW.w), 1e-5);
    farW /= max(abs(farW.w), 1e-5);
    ro = _CameraPos;
    rd = safeNorm(farW.xyz - nearW.xyz, float3(0, 0, 1));
    return;

    float3 target = cam_target;
    if (camera_preset == 0)
    {
        ro = float3(-4.9, 2.0, -7.8);
        target = float3(0.35, 5.4, 0.15);
    }
    else if (camera_preset == 1)
    {
        ro = float3(-2.7, 1.1, -5.2);
        target = float3(0.0, 4.8, 0.0);
    }
    else if (camera_preset == 2)
    {
        ro = float3(0.0, 2.0, -8.5);
        target = float3(0.0, 5.8, 0.2);
    }
    else if (camera_preset == 3)
    {
        ro = float3(5.5, 4.1, -3.5);
        target = float3(0.0, 4.2, 0.0);
    }
    else
    {
        float az = cam_orbit + rotate_speed * _Time * 30.0;
        sdf_orbitRay(az, cam_elevation, cam_distance, target, ndc, focal_length, ro, rd);
        return;
    }

    ro += cam_offset;
    float3 fwd = safeNorm(target + cam_offset - ro, float3(0,0,1));
    float3 rightV = safeNorm(cross(fwd, float3(0,1,0)), float3(1,0,0));
    float3 upV = cross(rightV, fwd);
    float roll = cam_roll;
    float3 rr = rightV * cos(roll) + upV * sin(roll);
    float3 uu = -rightV * sin(roll) + upV * cos(roll);
    rd = safeNorm(fwd * focal_length + ndc.x * rr + ndc.y * uu, fwd);
}

float3 materialColor(float matId, float3 p, float3 n)
{
    int m = (int)floor(matId + 0.001);
    float tint = frac(matId) / 0.25;
    float noise = n31(p * surface_noise_scale + tint);
    float edge = pow(1.0 - saturate(abs(dot(n, float3(0,1,0)))), 2.5);
    float wear = edge_wear_strength * (0.35 + 0.65 * noise);

    float3 c;
    if (m == 1) c = steel_color;
    else if (m == 2) c = dark_steel_color;
    else if (m == 3) c = rust_color;
    else if (m == 4) c = skylight_color * skylight_power;
    else if (m == 5) c = highlight_color;
    else c = dark_steel_color;

    if (m != 4)
    {
        c = lerp(c, rust_color, grime_amount * noise * 0.55);
        c = lerp(c, highlight_color, wear);
    }
    return c;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = (uv * 2.0 - 1.0) * float2(_Resolution.x / _Resolution.y, -1.0);

    float3 ro, rd;
    makeCamera(uv, ndc, ro, rd);

    float3 sun = sdf_sunDir(key_azimuth, key_elevation);
    float3 bg = lerp(float3(0.012, 0.013, 0.015), float3(0.055, 0.057, 0.060), pow(saturate(1.0 - uv.y), 2.0));
    bg += pow(saturate(dot(rd, sun)), 34.0) * skylight_color * skylight_power * 0.18;

    float matId;
    float t = sdf_march(ro, rd, max_distance, march_steps, matId);
    float3 col = bg;

    if (t > 0.0)
    {
        float3 pos = ro + rd * t;
        float3 n = sdf_calcNormal(pos);
        int m = (int)floor(matId + 0.001);
        float ao = sdf_calcAO(pos, n);
        float sha = 1.0;
        if (enable_shadows != 0 && m != 4)
        {
            sha = sdf_softShadow(pos + n * 0.025, sun, shadow_hardness, shadow_distance);
        }

        float3 albedo = materialColor(matId, pos, n);
        if (m == 4)
        {
            col = albedo * (1.0 + 0.08 * sin(_Time * 5.0 + pos.x));
        }
        else
        {
            col = sdf_shade(albedo, n, rd, sun, sha, ao, rim_power, 44.0);
            col += albedo * ambient_floor * ao;
        }

        float fog = 1.0 - exp(-fog_density * 0.08 * max(t - 1.0, 0.0));
        fog += saturate((pos.y - height_fog_start) * height_fog) * 0.12;
        col = lerp(col, bg * void_darkness, saturate(fog));
    }

    float2 q = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0);
    float vig = 1.0 - vignette_pregrade * saturate(dot(q, q) * 1.2);
    col *= vig;
    col += (h11(dot((float2)pixel, float2(13.1, 71.7)) + _Time * 19.0) - 0.5) * dust_amount;

    OutputUAV[pixel] = float4(max(col, 0.0), 1.0);
}
