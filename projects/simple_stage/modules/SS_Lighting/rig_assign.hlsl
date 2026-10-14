// SS_Lighting / rig_assign - which Fixture Rig record each slot plays (Map[slot] = record + 1, 0 = none).
// The plot's movers and strobes keep their own slots. Every other mover or strobe (a guest) takes, in rig order, a free
// slot of its role: first one the plot has no fixture in, then one whose plotted fixture the rig no longer has (it
// inherits that fixture's programming). Map[SS_SLOTS] counts placed guests, Map[SS_SLOTS + 1] those left with no free slot,
// and Map[SS_SLOTS + 2 + role] is the type the plot uses for that role (its native type, 0xFFFFFFFF when the plot has none).
#include "lighting.hlsli"
#include "../_shared/ss_rig.hlsli"

StructuredBuffer<SsRigFix> Fix:register(t0);
RWStructuredBuffer<uint> Map:register(u0);

bool liveMount(uint s){return s<_Data0_Count&&_Data0[s].active>.5;}

[numthreads(1,1,1)]void main(){
 for(uint s=0;s<SS_SLOTS+8u;s++)Map[s]=0u;
 for(uint k=0;k<SS_RIG_MAX;k++){SsRigFix f=Fix[k];
  bool own=ssFixActive(f)&&(f.flags&SS_FIX_PLOTTED)!=0u&&f.slot<SS_BAR0;
  if(own&&Map[f.slot]==0u)Map[f.slot]=k+1u;}
 for(uint r=0;r<4u;r++)Map[SS_SLOTS+2u+r]=0xFFFFFFFFu;
 for(uint n=0;n<SS_RIG_MAX;n++){SsRigFix f=Fix[n];
  if(ssFixActive(f)&&(f.flags&SS_FIX_PLOTTED)!=0u&&f.role<4u&&Map[SS_SLOTS+2u+f.role]==0xFFFFFFFFu)Map[SS_SLOTS+2u+f.role]=f.type;}
 uint placed=0u,unplaced=0u;
 for(uint g=0;g<SS_RIG_MAX;g++){SsRigFix f=Fix[g];
  bool guest=ssFixActive(f)&&(f.flags&SS_FIX_GUEST)!=0u&&(f.role==ROLE_MOVER||f.role==ROLE_STROBE);
  uint first=f.role==ROLE_MOVER?SS_MOVER0:SS_STROBE0,last=f.role==ROLE_MOVER?SS_MOVER0+SS_MOVERS:SS_STROBE0+SS_STROBES;
  uint pick=SS_RIG_NONE;
  if(guest){for(uint round2=0;round2<2u;round2++)for(uint s=first;s<last;s++){
   bool ok=pick==SS_RIG_NONE&&Map[s]==0u&&(round2==1u||!liveMount(s));pick=ok?s:pick;}}
  if(guest&&pick!=SS_RIG_NONE){Map[pick]=g+1u;placed++;}
  else if(guest)unplaced++;}
 Map[SS_SLOTS]=placed;Map[SS_SLOTS+1]=unplaced;
}
