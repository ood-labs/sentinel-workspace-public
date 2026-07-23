#include "types.hlsli"
StructuredBuffer<PNode> _Tex0 : register(t0);
StructuredBuffer<MassingState> _Tex1 : register(t1);
RWStructuredBuffer<PNode> OutputBuffer : register(u0);

float2 objectPivot(uint objectId) {
    float2 pivot = 0.0; float count = 0.0;
    [loop] for (uint i = 0u; i < PB_RECORD_COUNT; ++i) if (pbObjectForRecord(i) == objectId) { pivot += _Tex0[i].position.xz; count += 1.0; }
    return pivot / max(count, 1.0);
}

[numthreads(64,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x; if (i >= PB_RECORD_COUNT) return;
    PNode n = _Tex0[i]; uint objectId = pbObjectForRecord(i);
    if (objectId > 0u) {
        MassingState state = _Tex1[objectId - 1u]; float2 pivot = objectPivot(objectId);
        n.position.xz = pivot + pbRotate(n.position.xz - pivot, state.yaw_offset) + state.offset;
        n.yaw += state.yaw_offset; n.dir = float2(-sin(n.yaw), cos(n.yaw));
    }
    OutputBuffer[i] = n;
}
