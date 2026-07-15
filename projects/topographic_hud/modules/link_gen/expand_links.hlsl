// link_gen — derive connector links between node pairs (+ a big orbit arc) from
// the Nodes data port (data:0). Emits bezier-capable LinkRecords.

struct NodeRecord
{
    float2 pos; float radius; float intensity;
    float color_mix; float kind; float seed; float active;
};
struct LinkRecord
{
    float2 a; float2 b; float2 c; float2 d;
    float width; float group_id; float style; float intensity;
    float progress; float active; float curve; float pad0; // pad0: 0=link, 1=orbit
};

RWStructuredBuffer<LinkRecord> LinksOut : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 192u) return;

    LinkRecord L;
    L.a = float2(0, 0); L.b = float2(0, 0); L.c = float2(0, 0); L.d = float2(0, 0);
    L.width = 0; L.group_id = 0; L.style = 0; L.intensity = 0;
    L.progress = 0; L.active = 0; L.curve = 0; L.pad0 = 0;

    uint nodeCount = min((uint)_Data0_Count, 128u);
    uint orbitBase = (uint)link_count;
    uint orbitSegs = (orbit_arc != 0) ? 64u : 0u;

    if (i < (uint)link_count)
    {
        if (i < nodeCount)
        {
            NodeRecord na = _Data0[i];
            if (na.active > 0.5)
            {
                float2 a = na.pos;
                float2 b = a;
                if (link_mode == 3) b = _Data0[0].pos;              // Hub
                else if (link_mode == 2) b = float2(0.5, 0.5);      // Radial to center
                else if (link_mode == 1) { uint j = (i + 1u) % max(nodeCount, 1u); b = _Data0[j].pos; } // Chain
                else                                                 // Nearest
                {
                    float best = 1e9; uint bj = i;
                    [loop]
                    for (uint j = 0u; j < 128u; j++)
                    {
                        if (j >= nodeCount) break;
                        if (j != i && _Data0[j].active > 0.5)
                        {
                            float dd = distance(a, _Data0[j].pos);
                            if (dd < best && dd > min_dist && dd < max_dist) { best = dd; bj = j; }
                        }
                    }
                    b = _Data0[bj].pos;
                }

                float2 mid = (a + b) * 0.5;
                float2 dir = b - a;
                float2 perp = normalize(float2(-dir.y, dir.x) + float2(1e-5, 0.0));
                float bow = curve_amount * length(dir) * 0.5;

                L.a = a; L.b = b;
                L.c = lerp(a, mid, 0.5) + perp * bow;
                L.d = lerp(mid, b, 0.5) + perp * bow;
                L.width = width;
                L.group_id = (float)i;
                L.style = (dash != 0) ? 1.0 : 0.0;
                L.intensity = na.intensity;
                L.progress = draw_progress;
                L.active = (length(dir) > 0.02) ? 1.0 : 0.0;
                L.curve = (curve_amount > 0.01) ? 1.0 : 0.0;
                L.pad0 = 0.0;
            }
        }
    }
    else if (orbitSegs > 0u && i >= orbitBase && i < orbitBase + orbitSegs)
    {
        uint s = i - orbitBase;
        float a0 = (float)s / (float)orbitSegs * 6.2831853;
        float a1 = (float)(s + 1u) / (float)orbitSegs * 6.2831853;
        float spin = _Time * orbit_spin;
        float2 rad = float2(0.5625, 1.0) * orbit_radius;
        float2 A = float2(0.5, 0.5) + float2(cos(a0 + spin), sin(a0 + spin)) * rad;
        float2 B = float2(0.5, 0.5) + float2(cos(a1 + spin), sin(a1 + spin)) * rad;
        L.a = A; L.b = B; L.c = A; L.d = B;
        L.width = width * orbit_width;
        L.group_id = 1000.0;
        L.style = 0.0;
        L.intensity = 1.0;
        L.progress = 1.0;
        L.active = 1.0;
        L.curve = 0.0;
        L.pad0 = 1.0;
    }

    LinksOut[i] = L;
}
