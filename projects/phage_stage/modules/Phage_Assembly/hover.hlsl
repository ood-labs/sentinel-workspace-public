// Phage_Assembly / hover - which truss member the pointer is on, read live and never stored: the
// preview draws that member's tubes in ink and quiets the rest, the layout writes its card. One
// group: each thread measures a share of the member marks against the pointer (distance from the
// projected axis, less the truss band), then a groupshared reduction keeps the nearest within reach.
#include "assembly_types.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "axo.hlsli"
StructuredBuffer<PhMark> Marks:register(t0);
RWStructuredBuffer<float4> Hover:register(u0);   // [0] = (member or -1, distance px, -, -)
groupshared float gsD[64];
groupshared uint gsI[64];
[numthreads(64,1,1)]void main(uint gi:SV_GroupIndex){
 float2 R=_Resolution.xy,uv=_ViewportPointerPosition,p=uv*R;
 bool inside=all(uv>=0)&&all(uv<=1)&&p.y>axoHead(R);
 float best=1e9;uint bi=0xffffffffu;
 if(inside)[loop]for(uint k=gi;k<AM_SOLIDS-AM_MEMBERS;k+=64){PhMark m=Marks[AM_MEMBERS+k];
  if((uint)m.shape.x!=AM_MEMBER_KIND)continue;
  float d=phmSeg(p,m.geo.xy,m.geo.zw)-m.shape.y;if(d<best){best=d;bi=k;}}
 gsD[gi]=best;gsI[gi]=bi;GroupMemoryBarrierWithGroupSync();
 [unroll]for(uint s=32;s>0;s>>=1){if(gi<s&&gsD[gi+s]<gsD[gi]){gsD[gi]=gsD[gi+s];gsI[gi]=gsI[gi+s];}GroupMemoryBarrierWithGroupSync();}
 if(gi==0)Hover[0]=float4(gsD[0]<4*axoS(R)?(float)gsI[0]:-1,gsD[0],0,0);
}
