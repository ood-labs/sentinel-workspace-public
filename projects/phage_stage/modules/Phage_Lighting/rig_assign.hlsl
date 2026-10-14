// Phage_Lighting / rig_assign - which Fixture Rig record each PHAGE slot plays (Map[slot] = record + 1, 0 = none).
// The plot's movers and strobes keep their own slots. Every other mover or strobe (a guest) takes, in rig order, a free
// slot of its role: first one the anatomy has no mount for, then one whose plotted fixture the rig no longer has (it
// inherits that fixture's programming). Map[248] counts placed guests, Map[249] those left with no free slot, and
// Map[250 + role] is the type the plot uses for that role (its native type, 0xFFFFFFFF when the plot has none).
#include "lighting.hlsli"
#include "../_shared/phage_rig.hlsli"

StructuredBuffer<PhRigFix> Fix:register(t0);
RWStructuredBuffer<uint> Map:register(u0);

bool liveMount(uint s){return s<_Data0_Count&&_Data0[s].active>.5;}

[numthreads(1,1,1)]void main(){
 for(uint s=0;s<256u;s++)Map[s]=0u;
 for(uint k=0;k<PH_RIG_MAX;k++){PhRigFix f=Fix[k];
  bool own=phFixActive(f)&&(f.flags&PH_FIX_PLOTTED)!=0u&&f.slot<PH_BAR0;
  if(own&&Map[f.slot]==0u)Map[f.slot]=k+1u;}
 for(uint r=0;r<4u;r++)Map[250u+r]=0xFFFFFFFFu;
 for(uint n=0;n<PH_RIG_MAX;n++){PhRigFix f=Fix[n];
  if(phFixActive(f)&&(f.flags&PH_FIX_PLOTTED)!=0u&&f.role<4u&&Map[250u+f.role]==0xFFFFFFFFu)Map[250u+f.role]=f.type;}
 uint placed=0u,unplaced=0u;
 for(uint g=0;g<PH_RIG_MAX;g++){PhRigFix f=Fix[g];
  bool guest=phFixActive(f)&&(f.flags&PH_FIX_GUEST)!=0u&&(f.role==ROLE_MOVER||f.role==ROLE_STROBE);
  uint first=f.role==ROLE_MOVER?PH_MOVER0:PH_STROBE0,last=f.role==ROLE_MOVER?PH_MOVER0+PH_MOVERS:PH_STROBE0+PH_STROBES;
  uint pick=PH_RIG_NONE;
  if(guest){for(uint round2=0;round2<2u;round2++)for(uint s=first;s<last;s++){
   bool ok=pick==PH_RIG_NONE&&Map[s]==0u&&(round2==1u||!liveMount(s));pick=ok?s:pick;}}
  if(guest&&pick!=PH_RIG_NONE){Map[pick]=g+1u;placed++;}
  else if(guest)unplaced++;}
 Map[248]=placed;Map[249]=unplaced;
}
