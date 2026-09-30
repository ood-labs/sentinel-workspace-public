// Canvas marks for the arena drawing: every architecture box as a filled rectangle in plan (clip 1)
// and in section (clip 3), the phage silhouette as lines and rings (clip 2 plan, clip 4 section),
// the live bar emitters in their own colour (clip 2), and a record with the people and lit-bar
// counts. The preview draws them through tile bins instead of looping every record per pixel.
#include "../_shared/phage_venue.hlsli"
#include "../_shared/ph_marks.hlsli"
struct Architecture{float4 center,extent,surface,rotation;};StructuredBuffer<Architecture>A:register(t0);
struct Person{float4 p;float4 look;};StructuredBuffer<Person> C:register(t1);
struct Emitter{float4 a,b,radiance;};StructuredBuffer<Emitter> E:register(t2);
StructuredBuffer<float4> Sil:register(t3);
RWStructuredBuffer<PhMark> Marks:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "venue_view.hlsli"
float3 styleInk(float s){return s<.5?PT_INK:s<1.5?PT_MID:PT_DIM;}
float styleWidth(float s){return s<.5?2:s<1.5?1.4:1;}
PhMark rect(float4 r,float3 col,uint clip){PhMark m=(PhMark)0;m.geo=r;m.shape=float4(PHM_RECT,0,0,clip);m.fill=float4(col,1);return m;}
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=VM_TOTAL)return;
 venueView(_Resolution.xy);PhMark m=phmHidden();
 if(i<VM_SECTBOX){Architecture a=A[i];
  if(a.extent.w>.5&&a.center.w!=3&&a.rotation.x==0&&!(a.center.w==2&&a.extent.x>5)){
   float2 lo=max(a.center.xz-a.extent.xz,float2(-gHW,-gHL)),hi=min(a.center.xz+a.extent.xz,float2(gHW,gHL));
   if(all(lo<hi))m=rect(float4(planPx(float3(hi.x,0,lo.y)),planPx(float3(lo.x,0,hi.y))),
     a.center.w==0?PT_WELL:a.center.w==4?PT_GRID*1.6:a.center.w==2?PT_RULE:PT_GRID*1.2,1);}}
 else if(i<VM_SIL){Architecture a=A[i-VM_SECTBOX];
  if(a.extent.w>.5&&a.rotation.x==0&&!(a.center.w==1&&a.extent.z>1)){
   float2 lo=max(a.center.zy-a.extent.zy,float2(-gHL,floor_level-.4)),hi=min(a.center.zy+a.extent.zy,float2(gHL,floor_level+hall_height+.4));
   if(all(lo<hi))m=rect(float4(sectPx(float3(0,hi.y,lo.x)),sectPx(float3(0,lo.y,hi.x))),
     a.center.w==4?(a.extent.z>5?PT_GRID*.9:PT_GRID*1.6):a.center.w==2?(a.extent.x>5?PT_DIM:PT_GRID*1.3):a.center.w==0||a.center.w==3?PT_RULE:PT_GRID*1.2,3);}}
 else if(i<VM_EMIT){uint k=i-VM_SIL;
  if(Sil[0].w==260932&&k<(uint)Sil[0].z){float4 a=Sil[2+2*k],b=Sil[3+2*k];
   if(a.w>2.5){float2 c=planPx(a.xyz);m.geo=c.xyxy;m.shape=float4(PHM_RING,b.x*gS,1,2);m.stroke=float4(PT_RULE,.8);}
   else{bool plan=b.w<.5;m.geo=plan?float4(planPx(a.xyz),planPx(b.xyz)):float4(sectPx(a.xyz),sectPx(b.xyz));
    m.shape=float4(PHM_LINE,0,styleWidth(a.w),plan?2:4);m.stroke=float4(styleInk(a.w),1);}}}
 else if(i<VM_MARKS){Emitter e=E[i-VM_EMIT];
  if(e.b.w>.5){m.geo=float4(planPx(e.a.xyz),planPx(e.b.xyz));m.shape=float4(PHM_LINE,0,2.6,2);
   m.stroke=float4(dot(e.radiance.rgb,1)>.01?ptSampleColour(e.radiance.rgb):PT_RULE,1);}}
 else{uint people=0,lit=0;[loop]for(uint p=0;p<PV_PEOPLE;p++)if(C[p].p.w>.1)people++;
  [loop]for(uint e=0;e<PV_EMITTERS;e++)if(E[e].b.w>.5&&dot(E[e].radiance.rgb,1)>.01)lit++;
  m.fill=float4(people,lit,0,0);}
 Marks[i]=m;}
