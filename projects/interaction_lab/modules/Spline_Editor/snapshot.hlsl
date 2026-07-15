#include "types.hlsli"
StructuredBuffer<EditorState> _Tex0 : register(t0);
StructuredBuffer<SplineKnot> _Tex1 : register(t1);
RWStructuredBuffer<SplineKnot> OutputBuffer : register(u0);
[numthreads(1,1,1)]
void main(uint3 tid:SV_DispatchThreadID) {
    if((uint)round(_Tex0[0].command)!=1u) return;
    [loop] for(uint i=0u;i<64u;i++) OutputBuffer[i]=_Tex1[i];
}
