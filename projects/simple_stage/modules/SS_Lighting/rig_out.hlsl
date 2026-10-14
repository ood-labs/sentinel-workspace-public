// SS_Lighting / rig_out - the published Rig Fixtures: each record as rig_inst found it, with the slot rig_assign gave
// a guest (or SS_FIX_UNPLACED when every slot of its role is taken), and SS_FIX_NATIVE when its type is the one the
// plot uses for its role.
#include "lighting.hlsli"
#include "../_shared/ss_rig.hlsli"

StructuredBuffer<SsRigFix> Fix:register(t0);
StructuredBuffer<uint> Map:register(t1);
RWStructuredBuffer<SsRigFix> Out:register(u0);

[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){
 uint k=id.x;if(k>=SS_RIG_MAX)return;
 SsRigFix f=Fix[k];
 if((f.flags&SS_FIX_GUEST)!=0u&&(f.role==ROLE_MOVER||f.role==ROLE_STROBE)){
  uint s=SS_RIG_NONE;
  for(uint i=0;i<SS_BAR0;i++)s=(s==SS_RIG_NONE&&Map[i]==k+1u)?i:s;
  f.slot=s;if(s==SS_RIG_NONE)f.flags|=SS_FIX_UNPLACED;
 }
 if(ssFixActive(f)&&f.role<4u&&Map[SS_SLOTS+2u+f.role]==f.type)f.flags|=SS_FIX_NATIVE;
 Out[k]=f;
}
