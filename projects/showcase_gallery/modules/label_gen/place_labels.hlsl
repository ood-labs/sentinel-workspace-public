// label_gen — place technical-text label anchors near a subset of nodes (or on a
// ring / grid), derived from the Nodes data port (data:0).

struct NodeRecord
{
    float2 pos; float radius; float intensity;
    float color_mix; float kind; float seed; float active;
};
#include "label_edit_types.hlsli"

RWStructuredBuffer<LabelRecord> LabelsOut : register(u0);
StructuredBuffer<LabelOverride> _Tex1 : register(t1);

float h11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(48, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 48u) return;

    LabelRecord L;
    L.pos = float2(0, 0); L.scale = 1; L.label_id = 0;
    L.color_mix = 0; L.rotation = 0; L.active = 0; L.pad0 = 0;

    uint nodeCount = min((uint)_Data0_Count, 128u);
    uint activeNodeCount = 0u;
    [loop] for (uint scan = 0u; scan < nodeCount; ++scan)
        if (_Data0[scan].active > 0.5) activeNodeCount++;
    if (i < (uint)label_count)
    {
        if (attach_mode == 0 && activeNodeCount > 0u) // Nodes
        {
            uint desired = (uint)(h11((float)i * 3.1 + (float)seed * 7.0) * (float)activeNodeCount) % activeNodeCount;
            uint ni = 0u;
            uint rank = 0u;
            [loop] for (uint scan = 0u; scan < nodeCount; ++scan) {
                if (_Data0[scan].active < 0.5) continue;
                if (rank == desired) { ni = scan; break; }
                rank++;
            }
            NodeRecord n = _Data0[ni];
            if (n.active > 0.5)
            {
                L.pos = n.pos + float2(n.radius * 1.4 + 0.012, -0.008);
                L.active = 1.0;
            }
        }
        else if (attach_mode == 1) // Ring
        {
            float ang = (float)i / max((float)label_count, 1.0) * 6.2831853;
            L.pos = float2(0.5, 0.5) + float2(cos(ang), sin(ang)) * float2(0.5625, 1.0) * ring_radius;
            L.active = 1.0;
        }
        else // Grid
        {
            uint gx = i % 6u, gy = i / 6u;
            L.pos = float2(0.09 + (float)gx * 0.16, 0.12 + (float)gy * 0.14);
            L.active = 1.0;
        }

        L.pos += (float2(h11((float)i * 5.1), h11((float)i * 6.3)) - 0.5) * jitter;
        L.scale = scale * lerp(0.8, 1.2, h11((float)i * 2.2));
        L.label_id = floor(h11((float)i * 4.4 + (float)seed) * 8.0);
        L.color_mix = saturate(color_mix + (h11((float)i * 8.1) - 0.5) * 0.5);
        L.rotation = rotation;
        if (i < 12u) L.pos += _Tex1[i].offset;
        L.pos = clamp(L.pos, 0.02, 0.98);
    }

    LabelsOut[i] = L;
}
