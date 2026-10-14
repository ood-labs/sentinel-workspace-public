// One thread per item slot: each body box is drawn into both views by casting each covered pixel's viewing ray at
// the box, keeping the nearest hit per pixel (depth in the high 16 bits of the key, shade below).
#include "probe.hlsli"

StructuredBuffer<float4> Bounds : register(t5);
StructuredBuffer<PlanRecord> PlanIn : register(t6);
StructuredBuffer<Item> ItemsIn : register(t7);
RWStructuredBuffer<uint> Canvas : register(u0);
#define RP_SPAN 160

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x / RP_ENTRIES, e = id.x % RP_ENTRIES;
    if (i >= min(_Data0_Count, RP_FIXTURES) || !gdtfTablesValid() || !gdtfFixtureDecodable(i)) return;
    uint mode = gdtfModeGlobal(gdtfFixture(i));
    if (mode >= RP_MODES || e >= PlanIn[rpPlanHeader(mode)].r0.x) return;
    Item it = ItemsIn[id.x];
    uint node = (uint)(it.a.w + 0.5);
    float3 dims = gdtfGeometryDims(node);
    if (max(dims.x, max(dims.y, dims.z)) <= 0.0) return;
    float3 centre = 0.0;
    uint4 mlo = gdtfGeometry(node, 6u), mhi = gdtfGeometry(node, 7u);
    if (mlo.w != 0u)
    {
        float3 mn = asfloat(mlo.xyz), mx = asfloat(mhi.xyz), ext = mx - mn;
        float3 sc = float3(ext.x > 1e-6 ? dims.x / ext.x : 1.0, ext.y > 1e-6 ? dims.y / ext.y : 1.0,
                           ext.z > 1e-6 ? dims.z / ext.z : 1.0);
        centre = (mn + mx) * 0.5 * sc;
    }
    RigView v = rpView(Bounds[0], Bounds[1], RP_CANVAS_W, RP_CANVAS_H);
    float4 q = it.b;
    float3 c = it.a.xyz + rpRotate(q, centre), h = max(dims * 0.5, 0.004);
    float3 light = normalize(float3(0.35, 0.8, 0.5));
    [unroll] for (uint panel = 0u; panel < 2u; panel++)
    {
        float2 lo = 1e9, hi = -1e9;
        [unroll] for (uint k = 0u; k < 8u; k++)
        {
            float3 corner = c + rpRotate(q, h * float3((k & 1u) ? 1.0 : -1.0, (k & 2u) ? 1.0 : -1.0, (k & 4u) ? 1.0 : -1.0));
            float2 s = rpProject(v, panel, corner);
            lo = min(lo, s);
            hi = max(hi, s);
        }
        float x0 = v.panelW * panel, x1 = x0 + v.panelW;
        int2 a = int2(floor(max(lo, float2(x0, 0.0)))), b = int2(ceil(min(hi, float2(x1 - 1.0, RP_CANVAS_H - 1.0))));
        b = min(b, a + RP_SPAN);
        [loop] for (int py = a.y; py <= b.y; py++)
        [loop] for (int px = a.x; px <= b.x; px++)
        {
            float3 o, d;
            rpRay(v, panel, float2(px, py) + 0.5, o, d);
            float3 p = rpRotateInv(q, o - c), dl = rpRotateInv(q, d);
            float tmin = -1e30, tmax = 1e30;
            float3 n = 0.0;
            bool miss = false;
            [unroll] for (uint ax = 0u; ax < 3u; ax++)
            {
                float pa = ax == 0u ? p.x : (ax == 1u ? p.y : p.z);
                float da = ax == 0u ? dl.x : (ax == 1u ? dl.y : dl.z);
                float ha = ax == 0u ? h.x : (ax == 1u ? h.y : h.z);
                if (abs(da) < 1e-8) { miss = miss || abs(pa) > ha; continue; }
                float t1 = (-ha - pa) / da, t2 = (ha - pa) / da;
                float tn = min(t1, t2);
                if (tn > tmin)
                {
                    tmin = tn;
                    n = float3(ax == 0u ? 1.0 : 0.0, ax == 1u ? 1.0 : 0.0, ax == 2u ? 1.0 : 0.0) * (da > 0.0 ? -1.0 : 1.0);
                }
                tmax = min(tmax, max(t1, t2));
            }
            if (miss || tmin > tmax || tmax < 0.0) continue;
            float3 hit = o + d * tmin;
            float3 nw = rpRotate(q, n);
            float shade = 0.28 + 0.72 * saturate(dot(nw, light) * 0.5 + 0.5);
            uint depth = (uint)(rpDepth(v, panel, hit) * 65535.0);
            uint key = (depth << 16) | ((uint)(shade * 255.0) << 8) | 1u;
            uint dummy;
            InterlockedMax(Canvas[(py * RP_CANVAS_W + px) * 2u], key, dummy);
        }
    }
}
