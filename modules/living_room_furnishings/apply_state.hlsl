#include "types.hlsli"
StructuredBuffer<PNode> _Tex0 : register(t0);
StructuredBuffer<FurnishingState> _Tex1 : register(t1);
RWStructuredBuffer<PNode> OutputBuffer : register(u0);

float2 objectPivot(uint objectId) {
    float2 pivot = 0.0; float count = 0.0;
    [loop] for (uint i = 0u; i < LR_RECORD_COUNT; ++i) if (lrObjectForRecord(i) == objectId) {
        pivot += _Tex0[i].position.xz; count += 1.0;
    }
    return pivot / max(count, 1.0);
}

[numthreads(64,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x; if (i >= LR_RECORD_COUNT) return;
    PNode r = _Tex0[i]; uint objectId = lrObjectForRecord(i);
    FurnishingState state = _Tex1[objectId - 1u];
    float2 pivot = objectPivot(objectId);
    r.position.xz = pivot + lrRotate(r.position.xz - pivot, state.yaw_offset) + state.offset;
    r.yaw += state.yaw_offset;
    r.dir = float2(-sin(r.yaw), cos(r.yaw));
    OutputBuffer[i] = r;
}
