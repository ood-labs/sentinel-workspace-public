// Guest bodies: the rig's fixtures PHAGE's own models do not draw (any GDTF dropped onto the Fixture Rig), drawn from
// their types the way the fixture engine draws bodies: each type's bevelled boxes and cylinders from the FixtureRender
// tables, posed by pan and tilt and carried on the guest's live mount (vis_gframe, fe_render.hlsli's frame
// layout; vertex pulling, guest x part x 324 vertices). Shaded as PHAGE's mover housings are. The frame is PHAGE's
// stage, which is the Fixture Rig's, so no axis flip.
#include "taa.hlsli"
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"
#include "guests.hlsli"

#define PV 324u

struct VOut
{
    float4 Position : SV_POSITION;
    float3 world : TEXCOORD0;
    float3 normal : TEXCOORD1;
};

float edgeAt(uint k, float e, float b) { return k == 0u ? -e : (k == 1u ? -e + b : (k == 2u ? e - b : e)); }

VOut degenerate() { VOut o = (VOut)0; o.Position = float4(0, 0, -1, 1); return o; }

VOut VSMain(uint vid : SV_VertexID)
{
    uint g = vid / (FE_MAX_BODY_PARTS * PV);
    uint rem = vid % (FE_MAX_BODY_PARTS * PV);
    uint part = rem / PV, v = rem % PV;
    FePose pose;
    if (!guestPose(g, pose)) return degenerate();
    uint type = (uint)(pose.pt.w + 0.5);
    uint4 geo = FE_TYPE_GEO_AT(type);
    if (part >= geo.y) return degenerate();
    float4 a = FE_PART_G_AT((geo.x + part) * 3u);
    float3 c = FE_PART_G_AT((geo.x + part) * 3u + 1u).xyz;
    float4 s = FE_PART_G_AT((geo.x + part) * 3u + 2u);
    float3 p, n;
    if (a.x < 1.5)
    {
        // Bevelled box: 6 faces x 3 x 3 quads; corner quads are the rounded bevel.
        float3 e = 0.5 * s.xyz;
        float bevel = clamp(a.x > 0.5 ? a.z : 0.0015, 0.0005, 0.45 * min(e.x, min(e.y, e.z)));
        uint face = v / 54u, quad = (v % 54u) / 6u, k = v % 6u;
        uint ai = quad % 3u + ((k == 1u || k == 4u || k == 5u) ? 1u : 0u);
        uint bi = quad / 3u + ((k == 2u || k == 3u || k == 5u) ? 1u : 0u);
        float3 cube;
        if (face < 2u) cube = float3(edgeAt(ai, e.x, bevel), edgeAt(bi, e.y, bevel), face == 0u ? -e.z : e.z);
        else if (face < 4u) cube = float3(edgeAt(ai, e.x, bevel), face == 2u ? -e.y : e.y, edgeAt(bi, e.z, bevel));
        else cube = float3(face == 4u ? -e.x : e.x, edgeAt(ai, e.y, bevel), edgeAt(bi, e.z, bevel));
        float3 core = clamp(cube, -e + bevel, e - bevel);
        n = normalize(cube - core);
        p = c + core + n * bevel;
    }
    else
    {
        // Cylinder along axis s.w: 24 side quads, then two 24-triangle caps.
        if (v >= 288u) return degenerate();
        float radius = s.x, halfLen = 0.5 * s.y;
        float3 ax = s.w < 0.5 ? float3(1, 0, 0) : (s.w < 1.5 ? float3(0, 1, 0) : float3(0, 0, 1));
        float3 u = s.w < 0.5 ? float3(0, 1, 0) : float3(1, 0, 0);
        float3 w = cross(ax, u);
        uint seg = (v % 144u) / 6u, k = v % 6u;
        if (v < 144u)
        {
            uint sa = seg + ((k == 1u || k == 4u || k == 5u) ? 1u : 0u);
            float t = (k == 2u || k == 3u || k == 5u) ? 1.0 : -1.0;
            float ang = (float)sa * 6.2831853 / 24.0;
            float3 radial = u * cos(ang) + w * sin(ang);
            p = c + radial * radius + ax * halfLen * t;
            n = radial;
        }
        else
        {
            uint cap = (v - 144u) / 72u, tri = ((v - 144u) % 72u) / 3u, kk = (v - 144u) % 3u;
            float side = cap == 0u ? -1.0 : 1.0;
            float ang = (float)(tri + (kk == 2u ? 1u : 0u)) * 6.2831853 / 24.0;
            float3 radial = u * cos(ang) + w * sin(ang);
            p = c + ax * halfLen * side + (kk == 0u ? float3(0, 0, 0) : radial * radius);
            n = ax * side;
        }
    }
    uint space = (uint)(a.y + 0.5);
    p = fePosePoint(type, space, p, pose.pt.x, pose.pt.y);
    n = fePoseVector(space, n, pose.pt.x, pose.pt.y);
    VOut o;
    o.world = feToWorld(pose, p);
    o.normal = feRotate(pose, n);
    o.Position = taaClip(o.world);
    return o;
}

float4 PSMain(VOut i) : SV_TARGET0
{
    // movers.hlsl's housing: matte black under the work light's key, a soft sheen.
    float3 n = normalize(i.normal), v = normalize(_CameraPos - i.world), key = normalize(float3(-.5, .8, -.6));
    if (dot(n, v) < 0.0) n = -n;
    float diffuse = .22 + .78 * saturate(dot(n, key)), spec = pow(saturate(dot(reflect(-key, n), v)), 48);
    float3 col = (.025 * diffuse + .10 * spec) * worklight;
    return float4(col, length(i.world - _CameraPos));
}
