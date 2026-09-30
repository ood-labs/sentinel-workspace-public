// Posed truss members and solids (plate, sheath, collar, capsid, legs, booth, joints, spikes, riser).
StructuredBuffer<float4> DesignIn:register(t0);
StructuredBuffer<float4> A:register(t1);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
#include "kin_common.hlsli"
RWStructuredBuffer<PhMember> O:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=PH_MEMBERS)return;
 if(_Data0_Count<17||DesignIn[16].w!=260929){O[i]=(PhMember)0;return;}
 PhDesign D=phLoad();O[i]=phMember(D,PH_POSE_FROM(A),i);}
