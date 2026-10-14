// Canvas marks: for each of the two views, the pixel runs' pieces then every slot's mount, projected to canvas
// pixels with their live colour and selection. The preview draws these through tile bins.
#include "lighting.hlsli"
#include "../_shared/ss_marks.hlsli"
StructuredBuffer<SsOptical> O:register(t0);
StructuredBuffer<SsMount> Mounts:register(t1);
StructuredBuffer<float4> Sel:register(t2);
struct SsPiece{float4 a;float4 b;float4 n;float4 w;};StructuredBuffer<SsPiece> Pieces:register(t3);
RWStructuredBuffer<SsMark> Marks:register(u0);
#include "../_shared/plan_theme.hlsli"
#define LM_VIEW (SS_BARS*SS_BAR_SEGS+SS_SLOTS)
#define LM_MARKS (2*LM_VIEW)
float3 lit(float3 rgb,float level){return lerp(PT_WELL,ptSampleColour(rgb),saturate(level));}
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=LM_MARKS)return;
 float2 R=_Resolution.xy;bool ok=_Data0_Count>=SS_SLOTS&&Sel[0].w==SEL_MAGIC;SsMark m=ssmHidden();
 uint v=i/LM_VIEW,j=i%LM_VIEW;
 if(ok&&j<SS_BARS*SS_BAR_SEGS){if(j<_Data3_Count){SsPiece p=Pieces[j];if(p.w.z>.5){bool sel=Sel[SEL_SLOT0+SS_BAR0+(uint)round(p.n.w)].x>.5;
   m.geo=float4(toView(v,p.a.xyz,R),toView(v,p.b.xyz,R));m.shape=float4(SSM_LINE,0,sel?2.2:1.4,v+1);m.stroke=float4(sel?PT_ACCENT:PT_DIM,1);}}}
 else if(ok){uint f=j-SS_BARS*SS_BAR_SEGS;SsMount mt=Mounts[f];
  if(mt.active>.5&&mt.kind!=2){bool sel=Sel[SEL_SLOT0+f].x>.5;float2 q=toView(v,mt.position,R);
   if(mt.kind==0){SsOptical beam=O[f*SS_OPT_PER];m.geo=q.xyxy;m.shape=float4(SSM_DISC,4.5,1.2,v+1);
    m.fill=float4(lit(beam.colour,beam.intensity*.25),1);m.stroke=float4(sel?PT_ACCENT:PT_MID,1);}
   else if(mt.kind==1){SsStrobe st=ssStrobeOf(O[SS_OPT_STROBE0+f-SS_STROBE0]);float2 t=toView(v,mt.position+mt.up*.5*st.length,R)-q;if(length(t)<3)t=float2(5,0);
    m.geo=float4(q-t,q+t);m.shape=float4(SSM_TUBE,3,1,v+1);m.fill=float4(lit(st.plate_colour,st.plate+st.tube),1);m.stroke=float4(sel?PT_ACCENT:PT_MID,1);}
   else{m.geo=q.xyxy;m.shape=float4(SSM_DIAMOND,6,1.2,v+1);m.stroke=float4(sel?PT_ACCENT:PT_DIM,1);}}}
 Marks[i]=m;}
