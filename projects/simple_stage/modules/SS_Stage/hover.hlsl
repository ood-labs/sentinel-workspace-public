// SS_Stage / hover - what the pointer is on, read live and never stored: a fixture within reach first, else the
// nearest truss member. The preview draws it in ink and quiets the rest; the layout writes its card. One group: each
// thread measures a share of the marks against the pointer, then a groupshared reduction keeps the nearest.
#include "stage_types.hlsli"
#include "../_shared/ss_marks.hlsli"
#include "axo.hlsli"
StructuredBuffer<SsMark> Marks:register(t0);
RWStructuredBuffer<float4> Hover:register(u0);   // [0] = (member or -1, distance px, fixture slot or -1, -)
groupshared float gsD[64];
groupshared uint gsI[64];
groupshared float gsF[64];
groupshared uint gsS[64];
[numthreads(64,1,1)]void main(uint gi:SV_GroupIndex){
 float2 R=_Resolution.xy,uv=_ViewportPointerPosition,p=uv*R;
 bool inside=all(uv>=0)&&all(uv<=1)&&p.y>axoHead(R);
 float best=1e9,bestF=1e9;uint bi=0xffffffffu,bs=0xffffffffu;
 if(inside)[loop]for(uint k=gi;k<AM_MARKS-AM_MEMBERS;k+=64){SsMark m=Marks[AM_MEMBERS+k];uint kind=(uint)m.shape.x;
  float d=ssmSeg(p,m.geo.xy,m.geo.zw)-m.shape.y;
  if(kind==AM_MEMBER_KIND&&d<best){best=d;bi=k;}
  else if(kind==AM_FIX_KIND&&d<bestF){bestF=d;bs=(uint)m.fill.x;}}
 gsD[gi]=best;gsI[gi]=bi;gsF[gi]=bestF;gsS[gi]=bs;GroupMemoryBarrierWithGroupSync();
 [unroll]for(uint s=32;s>0;s>>=1){if(gi<s){if(gsD[gi+s]<gsD[gi]){gsD[gi]=gsD[gi+s];gsI[gi]=gsI[gi+s];}
   if(gsF[gi+s]<gsF[gi]){gsF[gi]=gsF[gi+s];gsS[gi]=gsS[gi+s];}}GroupMemoryBarrierWithGroupSync();}
 if(gi==0){float reach=5*axoS(R);bool fix=gsF[0]<reach;
  Hover[0]=float4(!fix&&gsD[0]<reach?(float)gsI[0]:-1,min(gsD[0],gsF[0]),fix?(float)gsS[0]:-1,0);}
}
