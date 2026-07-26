#include "types.hlsli"
StructuredBuffer<GizmoState> _Tex0:register(t0);StructuredBuffer<SceneObject> _Tex1:register(t1);RWStructuredBuffer<SceneObject> OutputBuffer:register(u0);
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint command=(uint)round(_Tex0[0].command);if(command!=1u&&command!=5u&&command!=6u)return;[loop]for(uint i=0u;i<16u;i++)OutputBuffer[i]=_Tex1[i];}
