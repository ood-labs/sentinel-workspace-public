#include "types.hlsli"
StructuredBuffer<LightEditorState> _Tex0:register(t0);StructuredBuffer<LightControlState> _Tex1:register(t1);RWStructuredBuffer<LightControlState> OutputBuffer:register(u0);
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint c=(uint)round(_Tex0[0].command);if(c!=1u&&c!=5u&&c!=6u)return;[unroll]for(uint i=0u;i<LC_OBJECT_COUNT;++i)OutputBuffer[i]=_Tex1[i];}
