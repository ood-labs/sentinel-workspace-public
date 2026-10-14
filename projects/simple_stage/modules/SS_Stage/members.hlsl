// SS_Stage / members - the solved truss members (tools/ss_stage.py writes them into _shared/ss_stage.hlsli).
#include "stage_types.hlsli"
#include "../_shared/ss_stage.hlsli"
RWStructuredBuffer<SsMember> O:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=TRUSS_MEMBERS)return;
 SsMember m;m.a=SS_MEMBER_DATA[i*4];m.b=SS_MEMBER_DATA[i*4+1];m.up=SS_MEMBER_DATA[i*4+2];m.meta=SS_MEMBER_DATA[i*4+3];O[i]=m;}
