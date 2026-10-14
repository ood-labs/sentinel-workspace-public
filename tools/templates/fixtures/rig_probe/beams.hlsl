// One thread per item slot: each lit beam is drawn into both views as a line from its origin, to the floor when it
// points down (at most 14 m), fading along its length; each pixel keeps its brightest beam (the key's top byte is
// the brightness, then 8-bit linear red, green and blue).
#include "probe.hlsli"

StructuredBuffer<float4> Bounds : register(t5);
StructuredBuffer<PlanRecord> PlanIn : register(t6);
StructuredBuffer<Item> ItemsIn : register(t7);
RWStructuredBuffer<uint> Canvas : register(u0);
#define RP_STEPS 2048

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x / RP_ENTRIES, e = id.x % RP_ENTRIES;
    if (i >= min(_Data0_Count, RP_FIXTURES) || !gdtfTablesValid() || !gdtfFixtureDecodable(i)) return;
    uint mode = gdtfModeGlobal(gdtfFixture(i));
    if (mode >= RP_MODES || e >= PlanIn[rpPlanHeader(mode)].r0.x) return;
    Item it = ItemsIn[id.x];
    uint node = (uint)(it.a.w + 0.5);
    if (gdtfGeometry(node, 0u).x != GDTF_GEO_BEAM || it.c.w <= 0.004) return;
    float3 rgb = it.c.rgb / max(max(it.c.r, max(it.c.g, it.c.b)), 1e-6) * saturate(it.c.w);
    if (max(rgb.r, max(rgb.g, rgb.b)) <= 0.004) return;
    RigView v = rpView(Bounds[0], Bounds[1], RP_CANVAS_W, RP_CANVAS_H);
    float3 o = it.a.xyz, d = normalize(rpRotate(it.b, float3(0.0, 0.0, -1.0)));
    float len = d.y < -1e-3 ? min(o.y / -d.y, 14.0) : 6.0;
    len = max(len, 0.1);
    [unroll] for (uint panel = 0u; panel < 2u; panel++)
    {
        float2 s0 = rpProject(v, panel, o), s1 = rpProject(v, panel, o + d * len);
        float2 delta = s1 - s0;
        int steps = clamp((int)ceil(max(abs(delta.x), abs(delta.y))), 1, RP_STEPS);
        bool steep = abs(delta.y) > abs(delta.x);
        float x0 = v.panelW * panel, x1 = x0 + v.panelW;
        [loop] for (int k = 0; k <= steps; k++)
        {
            float t = (float)k / (float)steps;
            float2 p = s0 + delta * t;
            float3 c = rgb * lerp(1.0, 0.3, t);
            uint key = ((uint)(max(c.r, max(c.g, c.b)) * 255.0) << 24) | ((uint)(c.r * 255.0) << 16) |
                       ((uint)(c.g * 255.0) << 8) | (uint)(c.b * 255.0);
            [unroll] for (int w = 0; w < 2; w++)
            {
                int2 q = int2(floor(p)) + (steep ? int2(w, 0) : int2(0, w));
                if (q.x < (int)x0 || q.x >= (int)x1 || q.y < 0 || q.y >= (int)RP_CANVAS_H) continue;
                uint dummy;
                InterlockedMax(Canvas[(q.y * RP_CANVAS_W + q.x) * 2u + 1u], key, dummy);
            }
        }
    }
}
