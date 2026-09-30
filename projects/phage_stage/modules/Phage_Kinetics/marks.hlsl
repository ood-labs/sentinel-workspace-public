// Canvas marks for the motion-control monitor: the rest pose ghosted under the live members in
// plan (clip 1) and front elevation (clip 2), and the live ankle rings. One anatomy call site per
// routine: each thread picks its leg and pose first, then only projects.
StructuredBuffer<float4> DesignIn:register(t0);
StructuredBuffer<float4> A:register(t1);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
#include "kin_common.hlsli"
StructuredBuffer<PhMember> Mem:register(t2);
#include "../_shared/ph_marks.hlsli"
#include "kin_view.hlsli"
RWStructuredBuffer<PhMark> Marks:register(u0);
#include "../_shared/plan_theme.hlsli"
PhMark mkLine(float2 a,float2 b,float w,float3 col,uint clip){PhMark m=(PhMark)0;m.geo=float4(a,b);m.shape=float4(PHM_LINE,0,w,clip);m.stroke=float4(col,1);return m;}
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=KM_MARKS)return;
 float2 R=_Resolution.xy;PhMark m=phmHidden();
 if(_Data0_Count<17||DesignIn[16].w!=260929){Marks[i]=m;return;}
 PhDesign D=phLoad();
 bool ghost=i<KM_PMEM||(i>=KM_EGHOST&&i<KM_EMEM),ankle=i>=KM_PANK&&i<KM_EGHOST;
 if(ghost||ankle){uint leg=ankle?i-KM_PANK:((i<KM_PMEM?i:i-KM_EGHOST)/2),part=i%2;
  PhPose pose=phRest();if(ankle)pose=PH_POSE_FROM(A);
  float3 h=phHip(D,pose,leg),k=phKnee(D,pose,leg),a=phAnkle(D,pose,leg);
  if(ankle){float lift=pose.lift[leg];m.geo=kvPlan(a,R).xyxy;m.shape=float4(PHM_RING,4+lift*3,1.5,1);m.stroke=float4(lift>.05?PT_ACCENT:PT_MID,1);}
  else{bool plan=i<KM_PMEM;float3 p0=part==0?h:k,p1=part==0?k:a;
   m=mkLine(plan?kvPlan(p0,R):kvElev(p0,R),plan?kvPlan(p1,R):kvElev(p1,R),1.5,PT_GRID*1.8,plan?1:2);}}
 else{bool plan=i<KM_PANK;PhMember r=Mem[plan?i-KM_PMEM:i-KM_EMEM];float kind=r.b.w,prof=r.up.w;
  if(kind>.5){bool chord=kind>7.5&&kind<9.5;
   if(plan){if(!(prof>1.5&&prof<4.5))m=mkLine(kvPlan(r.a.xyz,R),kvPlan(r.b.xyz,R),chord?2.4:1.3,chord?PT_INK:kind==7?PT_MID:PT_DIM,1);}
   else if(prof>1.5&&prof<2.5){m.geo=float4(kvElev(r.a.xyz,R),kvElev(r.b.xyz,R));m.shape=float4(PHM_FRAME,0,1,2);m.stroke=float4(PT_DIM,1);}
   else m=mkLine(kvElev(r.a.xyz,R),kvElev(r.b.xyz,R),chord?2.4:kind==14?2:1.3,chord?PT_INK:kind==7||kind==14?PT_MID:PT_DIM,2);}}
 Marks[i]=m;}
