// Fixture bodies: every instance draws its type's body parts (bevelled boxes and cylinders) posed by
// pan/tilt and its mount transform. Vertex pulling: instance x part x 324 vertices; unused slots degenerate.
// Parts and pivots come from the FixtureRender port.
// A placeholder (pose active -1: a type the engine cannot draw) is one alarm-colour box at its mount.
#define GDTF_RENDER _Data2
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"

StructuredBuffer<float4> Frame : register(t0);

#define PV 324u

struct VOut
{
    float4 Position : SV_POSITION;
    float3 world : TEXCOORD0;
    float3 normal : TEXCOORD1;
    nointerpolation float alarm : TEXCOORD2;
};

float edgeAt(uint k, float e, float b) { return k == 0u ? -e : (k == 1u ? -e + b : (k == 2u ? e - b : e)); }

VOut degenerate() { VOut o = (VOut)0; o.Position = float4(0, 0, -1, 1); return o; }

VOut VSMain(uint vid : SV_VertexID)
{
    uint inst = vid / (FE_MAX_BODY_PARTS * PV);
    uint rem = vid % (FE_MAX_BODY_PARTS * PV);
    uint part = rem / PV, v = rem % PV;
    if (inst >= FE_N_MAX) return degenerate();
    FePose pose;
    FE_LOAD_POSE(Frame, inst, pose);
    bool placeholder = pose.pt.z < -0.5;
    if (!placeholder && pose.pt.z < 0.5) return degenerate();
    uint type = 0u;
    float4 a = float4(0, 0, 0, 0), s = float4(FE_PLACEHOLDER_M, FE_PLACEHOLDER_M, FE_PLACEHOLDER_M, 0);
    float3 c = float3(0, 0, 0);
    if (placeholder)
    {
        if (part != 0u) return degenerate();
    }
    else
    {
        type = (uint)(pose.pt.w + 0.5);
        uint4 geo = FE_TYPE_GEO_AT(type);
        if (part >= geo.y) return degenerate();
        a = FE_PART_G_AT((geo.x + part) * 3u);
        c = FE_PART_G_AT((geo.x + part) * 3u + 1u).xyz;
        s = FE_PART_G_AT((geo.x + part) * 3u + 2u);
    }
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
    if (!placeholder)
    {
        uint space = (uint)(a.y + 0.5);
        p = fePosePoint(type, space, p, pose.pt.x, pose.pt.y);
        n = fePoseVector(space, n, pose.pt.x, pose.pt.y);
    }
    VOut o;
    o.alarm = placeholder ? 1.0 : 0.0;
    o.world = feToWorld(pose, p);
    o.normal = feRotate(pose, n);
    o.Position = mul(_ViewProjMatrix, float4(feView(o.world), 1.0));
    return o;
}

float4 PSMain(VOut i) : SV_TARGET
{
    float3 camW = feView(_CameraPos);
    float3 n = normalize(i.normal);
    float3 v = normalize(camW - i.world);
    if (dot(n, v) < 0.0) n = -n;
    // Matte black housings, read by a soft work light from the audience side and a cool top fill.
    float3 key = normalize(float3(0.3, 0.6, 0.75));
    float diff = saturate(dot(n, key)) * 0.8 + saturate(n.y) * 0.25 + 0.06;
    float3 h = normalize(key + v);
    float spec = pow(saturate(dot(n, h)), 40.0) * 0.08;
    float3 col = (0.028 * diff + spec) * worklight;
    // A placeholder shows the plan's alarm colour (plan_theme.hlsli PT_ALARM, a display value; present applies
    // gamma 2.2, so the linear value is its 2.2 power), shaded so its faces read.
    if (i.alarm > 0.5) col = pow(float3(1.000, 0.250, 0.300), 2.2) * (0.45 + 0.55 * saturate(diff)) * 0.9;
    return float4(col, length(feView(i.world) - _CameraPos));
}
