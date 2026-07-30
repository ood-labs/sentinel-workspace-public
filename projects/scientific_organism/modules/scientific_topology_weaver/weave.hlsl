struct EdgeRecord
{
    float2 a;
    float2 b;
    float weight;
    float phase;
    float distance;
    float tension;
    uint source_a;
    uint source_b;
    uint kind;
    uint flags;
};

RWStructuredBuffer<EdgeRecord> EdgesOut : register(u0);

float hash11(float p)
{
    return frac(sin(p * 91.173 + 17.71) * 43758.5453);
}

EdgeRecord emptyEdge(uint i)
{
    EdgeRecord e;
    e.a = 0.0;
    e.b = 0.0;
    e.weight = 0.0;
    e.phase = hash11((float)i);
    e.distance = 0.0;
    e.tension = 0.0;
    e.source_a = 0u;
    e.source_b = 0u;
    e.kind = 0u;
    e.flags = 0u;
    return e;
}

void finalizeEdge(inout EdgeRecord e, float confidence, float radius)
{
    float2 delta = (e.b - e.a) * float2(16.0 / 9.0, 1.0);
    e.distance = length(delta);
    float nearGate = smoothstep(min_link_distance, min_link_distance * 1.8, e.distance);
    float farGate = 1.0 - smoothstep(radius * 0.72, radius, e.distance);
    e.weight = saturate(confidence * nearGate * farGate);
    e.tension = saturate(e.distance / max(radius, 1e-3));
    if (e.weight > edge_floor) e.flags = 1u;
}

[numthreads(96, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= 96u) return;
    EdgeRecord e = emptyEdge(i);

    if (i < 48u)
    {
        uint ia = 16u + (i % 40u);
        uint ib = 16u + ((i * 7u + 13u) % 40u);
        e.a = _Data0[ia].position;
        e.b = _Data0[ib].position;
        e.source_a = _Data0[ia].stable_id;
        e.source_b = _Data0[ib].stable_id;
        e.kind = 0u;
        bool active = (_Data0[ia].flags & 1u) != 0u && (_Data0[ib].flags & 1u) != 0u;
        if (active) finalizeEdge(e, sqrt(_Data0[ia].confidence * _Data0[ib].confidence), link_radius);
    }
    else if (i < 64u)
    {
        uint blobSlot = (i - 48u) % 16u;
        uint cornerSlot = 16u + (((i - 48u) * 11u + 3u) % 40u);
        e.a = _Data0[blobSlot].position;
        e.b = _Data0[cornerSlot].position;
        e.source_a = _Data0[blobSlot].stable_id;
        e.source_b = _Data0[cornerSlot].stable_id;
        e.kind = 1u;
        bool active = (_Data0[blobSlot].flags & 1u) != 0u && (_Data0[cornerSlot].flags & 1u) != 0u;
        if (active) finalizeEdge(e, _Data0[blobSlot].confidence * _Data0[cornerSlot].confidence, link_radius * mass_reach);
    }
    else if (i < 80u)
    {
        uint lineSlot = 80u + (i - 64u);
        e.a = _Data0[lineSlot].aux.xy;
        e.b = _Data0[lineSlot].aux.zw;
        e.source_a = _Data0[lineSlot].stable_id;
        e.source_b = _Data0[lineSlot].stable_id;
        e.kind = 2u;
        if ((_Data0[lineSlot].flags & 1u) != 0u)
        {
            e.distance = length((e.b - e.a) * float2(16.0 / 9.0, 1.0));
            e.weight = _Data0[lineSlot].confidence;
            e.tension = saturate(e.distance / 0.18);
            e.flags = e.weight > edge_floor ? 1u : 0u;
        }
    }
    else
    {
        uint cornerSlot = 16u + (i - 80u) * 2u;
        e.a = _Data0[cornerSlot].position;
        e.b = e.a + _Data0[cornerSlot].velocity * velocity_reach * 0.04;
        e.source_a = _Data0[cornerSlot].stable_id;
        e.source_b = _Data0[cornerSlot].stable_id;
        e.kind = 3u;
        if ((_Data0[cornerSlot].flags & 1u) != 0u)
        {
            e.distance = length((e.b - e.a) * float2(16.0 / 9.0, 1.0));
            e.weight = saturate(_Data0[cornerSlot].confidence * length(_Data0[cornerSlot].velocity) * motion_weight);
            e.tension = saturate(e.distance * 8.0);
            e.flags = e.weight > edge_floor ? 1u : 0u;
        }
    }

    EdgesOut[i] = e;
}
