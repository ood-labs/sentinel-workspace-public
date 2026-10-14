// SS_Stage / marks - the axonometric's canvas marks: the floor grid as lines, one mark per truss member (its
// projected axis, banded by the truss width, carrying member index, bays and kind), one per solid (a disc covering its
// projected extent) and one per slot with a fixture (a head's mount to its body, a strobe's tube, a run's length).
// The preview expands only the marks in its tile. The last record holds the tube, solid, member and fixture counts.
#include "assembly.hlsli"
#include "../_shared/ss_marks.hlsli"
#include "axo.hlsli"
StructuredBuffer<SsMember> Mem:register(t0);
StructuredBuffer<Tube> T:register(t1);
StructuredBuffer<SsMount> Mounts:register(t2);
StructuredBuffer<SsPiece> Pieces:register(t3);
RWStructuredBuffer<SsMark> Marks:register(u0);
#include "../_shared/plan_theme.hlsli"
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=AM_TOTAL)return;
 float2 R=_Resolution.xy;float s=axoScale(R);SsMark m=ssmHidden();
 if(i<AM_MEMBERS){int k=(int)(i%AM_GRID_N)-AM_GRID_N/2;bool alongZ=i<AM_GRID_N;float e=AM_GRID_N/2;
  float3 a=alongZ?float3(k,0,-e):float3(-e,0,k),b=alongZ?float3(k,0,e):float3(e,0,k);
  m.geo=float4(axoAt(a,R),axoAt(b,R));m.shape=float4(SSM_LINE,0,1,0);m.stroke=float4(PT_GRID*2.5,1);}
 else if(i<AM_SOLIDS){uint j=i-AM_MEMBERS;SsMember r=Mem[j];
  if(r.b.w>.5&&r.up.w<.5){m.geo=float4(axoAt(r.a.xyz,R),axoAt(r.b.xyz,R));
   m.shape=float4(AM_MEMBER_KIND,r.a.w*s*.75+2,0,0);m.fill=float4(j,trussBays(r),r.b.w,0);}}
 else if(i<AM_FIX){uint j=i-AM_SOLIDS;Tube t=T[TUBE_COUNT+j];uint kind=(uint)t.a.w%10;
  if(kind!=0){float2 c=axoAt(t.a.xyz,R);m.geo=c.xyxy;m.shape=float4(AM_SOLID_KIND,length(float3(t.b.w,t.cutA.w,t.cutB.w))*s*1.3+4,0,0);m.fill=float4(j,0,0,0);}}
 else if(i<AM_MARKS){uint slot=i-AM_FIX;SsMount f=Mounts[slot];
  if(f.active>.5){uint kind=(uint)round(f.kind);float3 a=f.position,b=axoFixturePoint(f);float size=.22*SS_MOVER_SCALE*.5;
   if(kind==1){a=f.position-f.up*SS_STROBE_LENGTH*.5;b=f.position+f.up*SS_STROBE_LENGTH*.5;size=.08;}
   else if(kind==2){uint b0=(slot-SS_BAR0)*SS_BAR_SEGS;a=Pieces[b0].a.xyz;b=a;
    [loop]for(uint k=0;k<SS_BAR_SEGS;k++)if(Pieces[b0+k].w.z>.5)b=Pieces[b0+k].b.xyz;size=.06;}
   m.geo=float4(axoAt(a,R),axoAt(b,R));m.shape=float4(AM_FIX_KIND,max(size*s,3.0),0,0);m.fill=float4(slot,kind,f.extra.x,0);}}
 else{uint nt=0,ns=0,nm=0,nf=0;[loop]for(uint j=0;j<TRUSS_MEMBERS;j++){SsMember r=Mem[j];if(r.b.w<.5||r.up.w>.5)continue;
   nt+=round(r.b.w)==KIND_BLOCK?12:12+4*trussBays(r);nm++;}
  [loop]for(uint q=0;q<SOLID_COUNT;q++)if(T[TUBE_COUNT+q].a.w>.5)ns++;
  // a run counts its one metre battens (tools/ss_stage.py fills each piece with whole units)
  [loop]for(uint f=0;f<SS_SLOTS;f++)if(Mounts[f].active>.5){uint units=1;
   if(f>=SS_BAR0){float len=0;uint b0=(f-SS_BAR0)*SS_BAR_SEGS;[loop]for(uint k=0;k<SS_BAR_SEGS;k++)if(Pieces[b0+k].w.z>.5)len+=floor(Pieces[b0+k].w.x+1e-3);units=(uint)len;}
   nf+=units;}
  m.fill=float4(nt,ns,nm,nf);}
 Marks[i]=m;}
