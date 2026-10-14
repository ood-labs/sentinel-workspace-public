// Phage_Lighting / rig_words - the rig as the programmer sees it, for the Surface (control outputs rig_word0-15 and
// the counts): bit s of word s/16 is set while slot s plays a fixture of the rig (a mover or strobe slot with a record,
// a pixel run with a batten on it, the axes). Stat[16] = (movers, strobes, battens, guests placed); Stat[17] =
// (guests with no free slot, records drawn, pixel runs lit, 0).
#include "lighting.hlsli"
#include "../_shared/phage_rig.hlsli"

StructuredBuffer<PhMount> Mounts:register(t0);
StructuredBuffer<PhRigFix> Fix:register(t1);
StructuredBuffer<uint> Map:register(t2);
RWStructuredBuffer<float4> Stat:register(u0);

[numthreads(1,1,1)]void main(){
 uint runs=0;
 for(uint w=0;w<16u;w++){uint bits=0;
  for(uint b=0;b<16u;b++){uint s=w*16u+b;bool on=s<PH_SLOTS&&Mounts[s].active>.5;bits|=on?(1u<<b):0u;runs+=(on&&s>=PH_BAR0&&s<PH_AXIS0)?1u:0u;}
  Stat[w]=float4((float)bits,0,0,0);}
 uint movers=0,strobes=0,battens=0,drawn=0;
 for(uint k=0;k<PH_RIG_MAX;k++){PhRigFix f=Fix[k];bool on=phFixActive(f);
  movers+=(on&&f.role==ROLE_MOVER&&f.slot!=PH_RIG_NONE)?1u:0u;strobes+=(on&&f.role==ROLE_STROBE&&f.slot!=PH_RIG_NONE)?1u:0u;
  battens+=(on&&f.role==ROLE_BATTEN)?1u:0u;drawn+=on?1u:0u;}
 Stat[16]=float4(movers,strobes,battens,Map[248]);
 Stat[17]=float4(Map[249],drawn,runs,0);
 Stat[18]=0;Stat[19]=0;
}
