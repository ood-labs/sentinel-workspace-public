// Stage floor and truss pipes. Each fixture carries the pipe segment it hangs from (halfway to its row
// neighbours, from the prep pass), so a row of fixtures draws one continuous pipe.
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"

StructuredBuffer<float4> Frame : register(t0);

#define PIPE_SEG 12u

struct VOut
{
    float4 Position : SV_POSITION;
    float3 world : TEXCOORD0;
    float3 normal : TEXCOORD1;
    nointerpolation float material : TEXCOORD2;
};

VOut VSMain(uint vid : SV_VertexID)
{
    VOut o = (VOut)0;
    o.Position = float4(0, 0, -1, 1);
    if (vid < 6u)
    {
        float2 c = float2((vid == 1u || vid == 4u || vid == 5u) ? 1.0 : -1.0, (vid == 2u || vid == 3u || vid == 5u) ? 1.0 : -1.0);
        o.world = float3(c.x * 40.0, 0.0, lerp(-30.0, 25.0, c.y * 0.5 + 0.5));
        o.normal = float3(0, 1, 0);
        o.material = 0.0;
    }
    else
    {
        uint k = vid - 6u, inst = k / (PIPE_SEG * 6u), v = k % (PIPE_SEG * 6u);
        if (inst >= FE_N_MAX) return o;
        float4 A = Frame[inst * FE_FRAME_STRIDE + 4u], B = Frame[inst * FE_FRAME_STRIDE + 5u];
        if (B.w < 0.5) return o;
        float3 ax = B.xyz - A.xyz;
        float len = length(ax);
        if (len < 1e-4) return o;
        ax /= len;
        float3 u = abs(ax.y) < 0.9 ? normalize(cross(ax, float3(0, 1, 0))) : float3(1, 0, 0);
        float3 w = cross(ax, u);
        uint seg = v / 6u, c = v % 6u;
        float ang = (float)(seg + ((c == 1u || c == 4u || c == 5u) ? 1u : 0u)) * 6.2831853 / (float)PIPE_SEG;
        float t = (c == 2u || c == 3u || c == 5u) ? 1.0 : 0.0;
        float3 radial = u * cos(ang) + w * sin(ang);
        o.world = lerp(A.xyz, B.xyz, t) + radial * A.w;
        o.normal = radial;
        o.material = 1.0;
    }
    o.Position = mul(_ViewProjMatrix, float4(feView(o.world), 1.0));
    return o;
}

float4 PSMain(VOut i) : SV_TARGET
{
    float3 camW = feView(_CameraPos);
    float3 n = normalize(i.normal);
    float3 v = normalize(camW - i.world);
    float3 key = normalize(float3(0.3, 0.6, 0.75));
    float3 col;
    if (i.material < 0.5)
    {
        // Black-painted stage deck under the work light (the fixtures' light on it is added by the beam and
        // haze passes with the same board albedo).
        col = floor_albedo * feDeckAlbedo(i.world.xz) * 0.15 * (0.35 + 0.65 * saturate(dot(n, key))) * worklight.xxx;
    }
    else
    {
        float spec = pow(saturate(dot(reflect(-v, n), key)), 30.0) * 0.25;
        col = (0.05 * (0.3 + 0.7 * saturate(dot(n, key))) + spec) * worklight * float3(0.95, 0.96, 1.0);
    }
    return float4(col, length(feView(i.world) - _CameraPos));
}
