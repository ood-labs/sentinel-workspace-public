// industrial_surface_sampler - turns StructPart geometry into attachment points
// for greebles. Outputs stable surface frames with local UV.

struct StructPart {
    float3 center; float3 axis; float3 up; float3 half_extents;
    float length; float radius; float kind; float material;
    float seed; float group; float active; float spare;
};

struct SurfacePoint {
    float3 anchor;
    float3 normal;
    float3 tangent;
    float2 uv;
    float parent_kind;
    float parent_id;
    float seed;
    float weight;
    float active;
};

RWStructuredBuffer<SurfacePoint> Out : register(u0);

float h11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float2 h22(float p) { return float2(h11(p * 1.7 + 2.0), h11(p * 4.1 + 7.0)); }

float3 safeNorm(float3 v, float3 fb)
{
    float l = length(v);
    return l > 1e-4 ? v / l : fb;
}

void basisFromPart(StructPart p, out float3 rightV, out float3 upV, out float3 fwdV)
{
    fwdV = safeNorm(p.axis, float3(0,0,1));
    upV = safeNorm(p.up - fwdV * dot(p.up, fwdV), float3(0,1,0));
    rightV = safeNorm(cross(upV, fwdV), float3(1,0,0));
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 2048u) return;

    SurfacePoint s;
    s.anchor = 0; s.normal = float3(0,1,0); s.tangent = float3(1,0,0);
    s.uv = 0; s.parent_kind = 0; s.parent_id = 0; s.seed = (float)i; s.weight = 0; s.active = 0;

    uint parentCount = min((uint)_Data0_Count, (uint)max_parent_parts);
    if (parentCount == 0u) { Out[i] = s; return; }

    uint parent = i % parentCount;
    StructPart p = _Data0[parent];
    float sd = p.seed + (float)i * 19.37 + (float)seed * 101.0;

    bool allowed = p.active > 0.5;
    if ((int)p.kind == 0 && include_columns == 0) allowed = false;
    if (((int)p.kind == 1 || (int)p.kind == 2) && include_beams == 0) allowed = false;
    if ((int)p.kind == 3 && include_braces == 0) allowed = false;
    if ((int)p.kind == 4 && include_decks == 0) allowed = false;
    if ((int)p.kind == 6 && include_pipes == 0) allowed = false;
    if (!allowed) { Out[i] = s; return; }

    float3 r, u, f;
    basisFromPart(p, r, u, f);
    float2 rr = h22(sd);
    float facePick = h11(sd * 3.2 + 1.0);
    float3 local = (rr.xyx * 2.0 - 1.0) * p.half_extents;
    float3 nLocal;
    float3 tLocal;

    if (facePick < 0.34)
    {
        local.x = (h11(sd * 5.1) < 0.5 ? -1.0 : 1.0) * p.half_extents.x;
        nLocal = float3(sign(local.x), 0, 0);
        tLocal = float3(0, 0, 1);
    }
    else if (facePick < 0.66)
    {
        local.y = (h11(sd * 6.1) < underside_bias ? -1.0 : 1.0) * p.half_extents.y;
        nLocal = float3(0, sign(local.y), 0);
        tLocal = float3(1, 0, 0);
    }
    else
    {
        local.z = (h11(sd * 7.1) < joint_bias ? (h11(sd * 8.1) < 0.5 ? -1.0 : 1.0) : sign(local.z)) * p.half_extents.z;
        nLocal = float3(0, 0, sign(local.z));
        tLocal = float3(1, 0, 0);
    }

    float edge = max(abs(local.x) / max(p.half_extents.x, 0.01),
                     max(abs(local.y) / max(p.half_extents.y, 0.01),
                         abs(local.z) / max(p.half_extents.z, 0.01)));
    float edgeBoost = lerp(1.0, 1.8, saturate((edge - 0.72) * 3.5)) * edge_bias;

    s.anchor = p.center + r * local.x + u * local.y + f * local.z;
    s.normal = safeNorm(r * nLocal.x + u * nLocal.y + f * nLocal.z, u);
    s.tangent = safeNorm(r * tLocal.x + u * tLocal.y + f * tLocal.z, r);
    s.uv = saturate(local.xz / max(p.half_extents.xz * 2.0, float2(0.01, 0.01)) + 0.5);
    s.parent_kind = p.kind;
    s.parent_id = (float)parent;
    s.seed = sd;
    s.weight = saturate(edgeBoost * (0.45 + h11(sd * 9.3) * 0.75));
    s.active = h11(sd * 11.7) < sample_density * s.weight ? 1.0 : 0.0;

    Out[i] = s;
}
