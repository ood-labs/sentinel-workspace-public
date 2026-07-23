#include "types.hlsli"
StructuredBuffer<PNode> _Tex0 : register(t0);
struct ViewportObjectDescriptor { uint object_id; uint parent_id; float4x4 world_transform; float3 bounds_min; float3 bounds_max; float3 pivot; uint capability_flags; uint visible; uint selectable; };
RWStructuredBuffer<ViewportObjectDescriptor> OutputBuffer : register(u0);

void boundsFor(uint objectId, out float3 low, out float3 high) {
    low = 1e6; high = -1e6;
    [loop] for (uint i = 0u; i < PB_RECORD_COUNT; ++i) if (pbObjectForRecord(i) == objectId) {
        PNode n = _Tex0[i];
        float3 halfExtent = float3(n.width * 0.5, max(n.height * 0.5, 0.08), n.depth * 0.5);
        float3 center = n.position + float3(0, n.height * 0.5, 0);
        low = min(low, center - halfExtent); high = max(high, center + halfExtent);
    }
}

[numthreads(8,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x; if (i >= PB_OBJECT_COUNT) return;
    uint objectId = i + 1u; float3 low, high; boundsFor(objectId, low, high);
    float3 pivot = (low + high) * 0.5;
    ViewportObjectDescriptor d = (ViewportObjectDescriptor)0;
    d.object_id = objectId; d.world_transform = float4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, pivot.x,pivot.y,pivot.z,1);
    d.bounds_min = low - pivot; d.bounds_max = high - pivot; d.pivot = pivot;
    d.capability_flags = 3u; d.visible = 1u; d.selectable = 1u;
    OutputBuffer[i] = d;
}
