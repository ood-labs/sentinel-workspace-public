// Phage_Lighting / rig_out - the published Rig Fixtures: each record as rig_inst found it, with the slot rig_assign gave
// a guest (or PH_FIX_UNPLACED when every slot of its role is taken), and PH_FIX_NATIVE when its type is the one the
// plot uses for its role.
#include "lighting.hlsli"
#include "../_shared/phage_rig.hlsli"

StructuredBuffer<PhRigFix> Fix:register(t0);
StructuredBuffer<uint> Map:register(t1);
RWStructuredBuffer<PhRigFix> Out:register(u0);

[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){
 uint k=id.x;if(k>=PH_RIG_MAX)return;
 PhRigFix f=Fix[k];
 if((f.flags&PH_FIX_GUEST)!=0u&&(f.role==ROLE_MOVER||f.role==ROLE_STROBE)){
  uint s=PH_RIG_NONE;
  for(uint i=0;i<PH_BAR0;i++)s=(s==PH_RIG_NONE&&Map[i]==k+1u)?i:s;
  f.slot=s;if(s==PH_RIG_NONE)f.flags|=PH_FIX_UNPLACED;
 }
 if(phFixActive(f)&&f.role<4u&&Map[250u+f.role]==f.type)f.flags|=PH_FIX_NATIVE;
 Out[k]=f;
}
