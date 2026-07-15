#include "types.hlsli"
StructuredBuffer<EditorState> _Tex0 : register(t0);
StructuredBuffer<FurnishingState> _Tex1 : register(t1);
RWStructuredBuffer<FurnishingState> OutputBuffer : register(u0);
[numthreads(1,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint command = (uint)round(_Tex0[0].command);
    if (command != 1u && command != 5u && command != 6u) return;
    [loop] for (uint i=0u;i<LR_OBJECT_COUNT;++i) OutputBuffer[i]=_Tex1[i];
}
