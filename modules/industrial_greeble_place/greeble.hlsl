// industrial_greeble_place - converts surface samples into attached greeble
// records: bolts, plates, ribs, vents, boxes, clamps, conduit, welds, stains.

struct SurfacePoint {
    float3 anchor; float3 normal; float3 tangent; float2 uv;
    float parent_kind; float parent_id; float seed; float weight; float active;
};

struct GreeblePart {
    float3 anchor;
    float3 normal;
    float3 tangent;
    float2 uv;
    float3 size;
    float kind;
    float material;
    float parent_id;
    float seed;
    float active;
    float spare;
};

RWStructuredBuffer<GreeblePart> Out : register(u0);

float h11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float chooseKind(float r)
{
    float total = max(bolt_weight + plate_weight + rib_weight + vent_weight + box_weight +
                      clamp_weight + conduit_weight + weld_weight + stain_weight, 0.001);
    float x = r * total;
    if ((x -= bolt_weight) < 0.0) return 0.0;
    if ((x -= plate_weight) < 0.0) return 2.0;
    if ((x -= rib_weight) < 0.0) return 4.0;
    if ((x -= vent_weight) < 0.0) return 5.0;
    if ((x -= box_weight) < 0.0) return 7.0;
    if ((x -= clamp_weight) < 0.0) return 6.0;
    if ((x -= conduit_weight) < 0.0) return 8.0;
    if ((x -= weld_weight) < 0.0) return 9.0;
    return 10.0;
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 2048u) return;

    GreeblePart g;
    g.anchor = 0; g.normal = float3(0,1,0); g.tangent = float3(1,0,0);
    g.uv = 0; g.size = float3(0.02,0.02,0.01); g.kind = 0; g.material = 5;
    g.parent_id = 0; g.seed = (float)i; g.active = 0; g.spare = 0;

    if (i >= (uint)_Data0_Count) { Out[i] = g; return; }
    SurfacePoint s = _Data0[i];
    float sd = s.seed + (float)seed * 131.0;
    float density = greeble_density * lerp(background_detail_density, hero_detail_density, s.weight);
    density *= lerp(1.0, 1.6, edge_detail_boost * s.weight);
    if (s.active < 0.5 || h11(sd * 2.7) > density) { Out[i] = g; return; }

    float k = chooseKind(h11(sd * 4.1));
    float scale = lerp(scale_min, scale_max, h11(sd * 5.1)) * detail_scale;
    float rowSnap = max(row_alignment, 0.0);
    float2 snappedUv = lerp(s.uv, floor(s.uv * 14.0 + 0.5) / 14.0, saturate(rowSnap));
    float2 uvDelta = (snappedUv - s.uv) * 0.12;
    float3 bitan = normalize(cross(s.normal, s.tangent));

    g.anchor = s.anchor + s.normal * 0.006 + s.tangent * uvDelta.x + bitan * uvDelta.y;
    g.normal = s.normal;
    g.tangent = normalize(lerp(s.tangent, bitan, (h11(sd * 6.3) < symmetry_amount) ? 0.0 : 0.35));
    g.uv = snappedUv;
    g.kind = k;
    g.parent_id = s.parent_id;
    g.seed = sd;
    g.active = 1.0;

    if (k == 0.0)      { g.size = float3(scale * 0.045, scale * 0.045, scale * 0.020); g.material = 5.0; }
    else if (k == 2.0) { g.size = float3(scale * 0.18,  scale * 0.10,  scale * 0.020); g.material = 1.0; }
    else if (k == 4.0) { g.size = float3(scale * 0.035, scale * 0.28,  scale * 0.025); g.material = 5.0; }
    else if (k == 5.0) { g.size = float3(scale * 0.18,  scale * 0.14,  scale * 0.018); g.material = 2.0; }
    else if (k == 6.0) { g.size = float3(scale * 0.08,  scale * 0.055, scale * 0.035); g.material = 3.0; }
    else if (k == 7.0) { g.size = float3(scale * 0.14,  scale * 0.18,  scale * 0.055); g.material = 2.0; }
    else if (k == 8.0) { g.size = float3(scale * 0.035, scale * 0.42,  scale * 0.030); g.material = 3.0; }
    else if (k == 9.0) { g.size = float3(scale * 0.025, scale * 0.36,  scale * 0.010); g.material = 3.0; }
    else               { g.size = float3(scale * 0.20,  scale * 0.42,  scale * 0.004); g.material = 3.0; }

    Out[i] = g;
}
