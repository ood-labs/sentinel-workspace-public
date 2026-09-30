// Posed fixture mounts for every stable slot (movers ride the capsid, knees and feet).
StructuredBuffer<float4> DesignIn:register(t0);
StructuredBuffer<float4> A:register(t1);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
#include "kin_common.hlsli"
RWStructuredBuffer<PhMount> M:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint s=id.x;if(s>=PH_SLOTS)return;
 if(_Data0_Count<17||DesignIn[16].w!=260929){M[s]=(PhMount)0;return;}
 PhDesign D=phLoad();M[s]=phMountFull(D,PH_POSE_FROM(A),s);}
