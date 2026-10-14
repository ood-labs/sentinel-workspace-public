// One thread per (fixture, plan entry): the entry's geometry posed in stage metres. The pose composes each entry
// from the mode's root down: the fixture's mount, every geometry's position (a template root takes its reference's
// instead) and the angle its Pan or Tilt channel decodes to (right-hand about the geometry's Z or X). A Beam takes
// its cell's colour and dimmer level when it is in a cell, else the fixture's colour, and always the fixture's
// dimmer level and shutter.
#include "probe.hlsli"

StructuredBuffer<StateRecord> StateIn : register(t4);
StructuredBuffer<float4> CellColourIn : register(t5);
StructuredBuffer<PlanRecord> PlanIn : register(t6);
RWStructuredBuffer<Item> Items : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x / RP_ENTRIES, e = id.x % RP_ENTRIES;
    if (i >= min(_Data0_Count, RP_FIXTURES) || !gdtfTablesValid() || !gdtfFixtureDecodable(i)) return;
    GdtfFixture f = gdtfFixture(i);
    uint mode = gdtfModeGlobal(f);
    if (mode >= RP_MODES || e >= PlanIn[rpPlanHeader(mode)].r0.x) return;
    uint base = rpPlanHeader(mode) + 1u;

    uint chain[16];
    uint n = 0u;
    uint k = e;
    [loop] while (k != GDTF_NONE && n < 16u)
    {
        chain[n++] = k;
        k = PlanIn[base + k].r0.y;
    }
    float3x3 R = gdtfFixtureAxes(i);
    float3 t = gdtfFixtureOrigin(i);
    [loop] for (uint j = n; j > 0u; j--)
    {
        PlanRecord pe = PlanIn[base + chain[j - 1u]];
        if ((pe.r0.w & RP_SKIP_OWN) == 0u)
        {
            float3x4 m = gdtfGeometryLocal(pe.r0.x);
            t += mul(R, float3(m[0].w, m[1].w, m[2].w));
            R = mul(R, float3x3(m[0].xyz, m[1].xyz, m[2].xyz));
        }
        if (pe.r1.x != GDTF_NONE)
        {
            GdtfValue v = gdtfChannelValue(f, pe.r1.x);
            uint want = pe.r1.y == 0u ? GDTF_ATTR_PAN : GDTF_ATTR_TILT;
            if (v.function != GDTF_NONE && (gdtfFunction(v.function, 0u).x & 0xFFFFu) == want)
            {
                float s, c;
                sincos(radians(v.physical), s, c);
                R = mul(R, pe.r1.y == 0u ? float3x3(c, -s, 0, s, c, 0, 0, 0, 1) : float3x3(1, 0, 0, 0, c, -s, 0, s, c));
            }
        }
    }
    PlanRecord self = PlanIn[base + e];
    uint node = self.r0.x;
    float3 x = normalize(mul(R, float3(1, 0, 0))), y = normalize(mul(R, float3(0, 1, 0)));
    float3 z = normalize(cross(x, y));
    y = cross(z, x);
    Item it;
    it.a = float4(t, (float)node);
    it.b = rpQuat(x, y, z);
    it.c = 0.0;
    if (gdtfGeometry(node, 0u).x == GDTF_GEO_BEAM)
    {
        StateRecord st = StateIn[i];
        float3 rgb = st.s1.rgb;
        float level = 1.0;
        uint cell = self.r0.z;
        if (cell != GDTF_NONE && cell < RP_CELLS)
        {
            float4 cc = CellColourIn[i * RP_CELLS + cell];
            rgb = cc.rgb;
            level = cc.w;
        }
        it.c = float4(rgb, st.s0.x * level);
    }
    Items[id.x] = it;
}
