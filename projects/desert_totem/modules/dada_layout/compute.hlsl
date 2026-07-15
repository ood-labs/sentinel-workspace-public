#include "dada_edit_types.hlsli"

RWStructuredBuffer<DadaPart> PartsOut : register(u0);
StructuredBuffer<AssemblyOverride> _Tex0 : register(t0);

#define M_BLACK  2.0
#define M_WHITE  3.0
#define M_RED    10.0
#define M_YELLOW 11.0
#define M_ORANGE 12.0
#define M_OLIVE  13.0
#define M_GRAY   14.0
#define M_BLACKG 15.0
#define M_WHITEG 16.0
#define M_GOLD   17.0

#define K_SPHERE 0.0
#define K_BOX 1.0
#define K_CONE 2.0
#define K_DISC 3.0
#define K_HOOP 4.0
#define K_CRESCENT 5.0
#define K_LENS 6.0
#define K_BEACH 7.0
#define K_BALUSTER 8.0
#define K_BOWL 9.0
#define K_HARLEQ 10.0

DadaPart mk(float3 pos, float3 sc, float3 rot, float kind, float mat, float grp, float3 pp)
{
    DadaPart d;
    d.pos_xy = pos.xy; d.pos_z = pos.z;
    d.sc_xy = sc.xy; d.sc_z = sc.z;
    d.yaw = rot.x; d.tilt = rot.y; d.roll = rot.z;
    d.kind = kind; d.mat = mat; d.group = grp;
    d.p0 = pp.x; d.p1 = pp.y; d.p2 = pp.z; d.active = 1.0;
    return d;
}
DadaPart sph(float3 pos, float r, float mat, float grp) { return mk(pos, r.xxx, 0.0.xxx, K_SPHERE, mat, grp, 0.0.xxx); }
float h11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }

#define NPARTS 29

DadaPart basePart(uint i)
{
    if (i == 0)  return sph(float3(0.00, 8.55, 0.05), 0.46, M_BLACKG, 1);
    if (i == 1)  return mk(float3(0.00, 8.02, 0.05), 0.34.xxx, 0.0.xxx, K_CONE, M_BLACK, 1, float3(0.147, 0.824, 0));
    if (i == 2)  return sph(float3(0.90, 8.35, 0.15), 0.40, M_RED, 1);
    if (i == 3)  return sph(float3(-0.42, 9.05, 0.00), 0.28, M_RED, 1);
    if (i == 4)  return sph(float3(1.75, 7.05, 0.30), 0.52, M_RED, 2);
    if (i == 5)  return mk(float3(2.05, 7.40, -0.05), 1.32.xxx, 0.0.xxx, K_CRESCENT, M_WHITE, 2, float3(-0.394, 0.379, 0.803));
    if (i == 6)  return mk(float3(0.05, 6.45, 0.20), 1.00.xxx, 0.0.xxx, K_LENS, M_WHITE, 2, 0.0.xxx);
    if (i == 7)  return mk(float3(-2.20, 6.55, 0.10), 0.98.xxx, float3(0.45,1.15,0), K_HOOP, M_GOLD, 2, float3(0.046,0,0));
    if (i == 8)  return mk(float3(-1.70, 3.78, 0.35), 0.42.xxx, float3(0.55,0,0), K_BOX, M_RED, 3, 0.0.xxx);
    if (i == 9)  return mk(float3(0.62, 4.05, 0.55), float3(0.55,0.32,0.42), 0.0.xxx, K_BOX, M_YELLOW, 3, 0.0.xxx);
    if (i == 10) return sph(float3(-0.95, 4.12, 0.55), 0.36, M_BLACKG, 3);
    if (i == 11) return mk(float3(0.10, 4.85, 0.95), 0.55.xxx, 0.0.xxx, K_HARLEQ, M_YELLOW, 3, float3(0.65,0,0));
    if (i == 12) return mk(float3(1.45, 4.235, 0.70), 1.00.xxx, 0.0.xxx, K_BALUSTER, M_WHITE, 3, 0.0.xxx);
    if (i == 13) return mk(float3(0.05, 4.05, 0.78), 0.36.xxx, 0.0.xxx, K_BOWL, M_BLACKG, 3, 0.0.xxx);
    if (i == 14) return mk(float3(-2.25, 4.85, 0.35), 0.72.xxx, 0.0.xxx, K_BEACH, M_WHITE, 3, 0.0.xxx);
    if (i == 15) return mk(float3(-1.55, 3.10, 0.55), 0.55.xxx, float3(0,1.40,0), K_HOOP, M_GOLD, 3, float3(0.064,0,0));
    if (i == 16) return sph(float3(-0.30, 3.05, 1.00), 0.34, M_WHITEG, 3);
    if (i == 17) return sph(float3(0.38, 3.00, 1.00), 0.32, M_GRAY, 3);
    if (i == 18) return sph(float3(1.02, 2.95, 1.00), 0.30, M_OLIVE, 3);
    if (i == 19) return mk(float3(-1.15, 1.70, 0.15), 1.15.xxx, 0.0.xxx, K_CONE, M_RED, 4, float3(0.052, 0.435, 0));
    if (i == 20) return mk(float3(1.70, 1.65, 0.30), 0.70.xxx, 0.0.xxx, K_DISC, M_BLACKG, 4, float3(0.071,0,0));
    if (i == 21) return sph(float3(-2.35, 2.70, 0.05), 0.26, M_YELLOW, 4);
    if (i == 22) return sph(float3(-2.35, 1.92, 0.05), 0.24, M_BLACKG, 4);
    if (i == 23) return sph(float3(-2.35, 1.20, 0.05), 0.24, M_ORANGE, 4);
    if (i == 24) return sph(float3(0.15, 1.30, 0.40), 0.30, M_BLACKG, 4);
    if (i == 25) return sph(float3(1.75, 5.78, 0.30), 0.093, M_BLACKG, 2);
    if (i == 26) return sph(float3(1.75, 6.11, 0.30), 0.093, M_GOLD, 2);
    if (i == 27) return sph(float3(1.75, 6.44, 0.30), 0.093, M_BLACKG, 2);
    if (i == 28) return sph(float3(1.75, 6.77, 0.30), 0.093, M_GOLD, 2);
    return sph(0.0.xxx, 0.0, M_WHITE, 0);
}

float2 groupPivot(uint groupId)
{
    if (groupId == 1u) return float2(0.10, 8.48);
    if (groupId == 2u) return float2(0.48, 6.70);
    if (groupId == 3u) return float2(-0.20, 3.82);
    return float2(-0.45, 1.65);
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 128u) return;
    if (i >= (uint)NPARTS) {
        DadaPart z = sph(0.0.xxx, 0.0, M_WHITE, 0); z.active = 0.0; PartsOut[i] = z; return;
    }

    DadaPart d = basePart(i);
    uint groupId = (uint)round(d.group);
    AssemblyOverride edit = _Tex0[min(groupId - 1u, 3u)];
    float2 pivot = groupPivot(groupId);
    float cs = cos(edit.rotation), sn = sin(edit.rotation);
    float2 local = d.pos_xy - pivot;
    local = float2(cs * local.x - sn * local.y, sn * local.x + cs * local.y) * max(edit.scale, 0.01);
    d.pos_xy = pivot + local + edit.offset;
    d.roll += edit.rotation;
    d.sc_xy *= max(edit.scale, 0.01);
    d.sc_z *= max(edit.scale, 0.01);

    static const float3 CENTER = float3(0.0, 4.5, 0.3);
    float3 pos = float3(d.pos_xy, d.pos_z);
    pos = CENTER + (pos - CENTER) * spread;
    float2 rad = pos.xz - CENTER.xz;
    float rl = length(rad) + 1e-4;
    pos.xz += (rad / rl) * explode;
    float3 jit = float3(h11(i * 1.73 + seed * 3.1) - 0.5,
                        h11(i * 2.91 + seed * 1.3) - 0.5,
                        h11(i * 4.13 + seed * 2.7) - 0.5);
    pos += jit * jitter;
    pos.y += lift;
    d.pos_xy = pos.xy; d.pos_z = pos.z;
    d.sc_xy *= size_mul; d.sc_z *= size_mul;
    PartsOut[i] = d;
}
