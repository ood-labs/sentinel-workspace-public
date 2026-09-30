// Canvas marks for the axonometric: the floor grid as lines, then one mark per truss member (its
// projected axis, banded by the truss width, carrying member index and bay count) and one per solid
// (a disc covering its projected extent). The preview expands only the members and solids in its
// tile into their real tubes and edges. The last record holds the tube and solid counts.
#include "assembly_types.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "axo.hlsli"
StructuredBuffer<PhMember> Mem:register(t0);
StructuredBuffer<Tube> T:register(t1);
RWStructuredBuffer<PhMark> Marks:register(u0);
#include "../_shared/plan_theme.hlsli"
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=AM_TOTAL)return;
 float2 R=_Resolution.xy;float s=axoScale(R);PhMark m=phmHidden();
 if(i<AM_MEMBERS){int k=(int)(i%9)-4;bool alongZ=i<9;
  float3 a=alongZ?float3(k*5,0,-20):float3(-20,0,k*5),b=alongZ?float3(k*5,0,20):float3(20,0,k*5);
  m.geo=float4(axoAt(a,R),axoAt(b,R));m.shape=float4(PHM_LINE,0,1,0);m.stroke=float4(PT_GRID*2,1);}
 else if(i<AM_SOLIDS){uint j=i-AM_MEMBERS;if(j<_Data0_Count){PhMember r=Mem[j];
   if(r.b.w>.5&&r.up.w<.5){uint bays=clamp((uint)ceil(length(r.b.xyz-r.a.xyz)/(r.a.w*1.15)),1u,15u);
    m.geo=float4(axoAt(r.a.xyz,R),axoAt(r.b.xyz,R));m.shape=float4(AM_MEMBER_KIND,r.a.w*s*.75+2,0,0);m.fill=float4(j,bays,0,0);}}}
 else if(i<AM_MARKS){uint j=i-AM_SOLIDS;Tube t=T[TUBE_COUNT+j];uint kind=(uint)t.a.w%10;
  if(kind!=0){float2 c=axoAt(t.a.xyz,R);m.geo=c.xyxy;m.shape=float4(AM_SOLID_KIND,max(max(t.b.w,t.cutA.w),t.cutB.w)*s*2.2+4,0,0);m.fill=float4(j,0,0,0);}}
 else{uint nt=0,ns=0;[loop]for(uint j=0;j<TRUSS_MEMBERS&&j<_Data0_Count;j++){PhMember r=Mem[j];if(r.b.w<.5||r.up.w>.5)continue;
   nt+=12+4*clamp((uint)ceil(length(r.b.xyz-r.a.xyz)/(r.a.w*1.15)),1u,15u);}
  [loop]for(uint q=0;q<SOLID_COUNT;q++)if(T[TUBE_COUNT+q].a.w>.5)ns++;
  m.fill=float4(nt,ns,0,0);}
 Marks[i]=m;}
