// Mapping_Editor / editor - the editing canvas, the DRAWING only: the mapped extent, the warped
// lattice, the zoning masks with the selected one's handles, the polygon being drawn, the 25
// mapping handles and the box selection. The side panel (edit mode, mask tools, one row per mask),
// the title and status, the hover highlights and inspector, and the keycap verbs are recorded by
// layout.hlsl and drawn over this by the shared UI kit (ui.hlsl).
#include "mapping.hlsli"
#include "../_shared/ui/il_core.hlsli"
RWTexture2D<float4> OutputUAV:register(u0);
StructuredBuffer<float4> Calib:register(t0);
StructuredBuffer<float4> C:register(t2);
StructuredBuffer<float4> G:register(t3);   // warped lattice, world space, from gridpts
StructuredBuffer<float4> M:register(t4);   // zoning masks
#include "canvas_view.hlsli"
#include "masks.hlsli"
float seg(float2 p,float2 a,float2 b){float2 d=b-a;return length((p-a)-d*saturate(dot(p-a,d)/max(dot(d,d),1e-12)));}
float2 screen(float2 p){return canvasPixel(p,C[0]);}
[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){
 if(any(id.xy>=(uint2)_Resolution))return;
 float2 px=id.xy+.5,uv=px/_Resolution;
 float2 w=canvasWorld(uv,C[0]);
 float bound=.4/extent_a;float2 lo=.5-bound,hi=.5+bound;
 bool inside=all(w>=lo)&&all(w<=hi);
 float3 col=inside?IL_WELL:IL_FIELD;
 float2 a=screen(lo),b=screen(hi);
 float border=min(min(seg(px,a,float2(b.x,a.y)),seg(px,float2(b.x,a.y),b)),min(seg(px,b,float2(a.x,b.y)),seg(px,float2(a.x,b.y),a)));
 col=lerp(col,IL_RULE,1-smoothstep(.5,1.5,border));
 // Draw the entire warped grid, including off-output portions for editing.
 // Points come precomputed from the gridpts pass; the world->pixel transform is
 // hoisted out of the loop, so this costs one mad and one seg() per point
 // instead of a full mappedUV() evaluation per point per pixel.
 float sc=C[0].z*canvasScale();float2 off=.5*_Resolution-C[0].xy*sc;
 [loop]for(int axis=0;axis<2;axis++)[loop]for(int row=0;row<5;row++){
  int base=axis*165+row*33;
  float2 last=G[base].xy*sc+off;
  [loop]for(int j=1;j<=32;j++){
   float2 at=G[base+j].xy*sc+off;
   col=lerp(col,inside?IL_MID:IL_DIM,1-smoothstep(.65,1.65,seg(px,last,at)));
   last=at;
  }
 }

 // Zoning masks. Block zones are the one safety-critical state on this canvas, so they take the
 // alarm red: outline and hatch. Only-In zones are ink. The dashed line is the Calibration's own
 // margin-adjusted zone, i.e. exactly where Adaptive Mapping cuts the beam. The selected mask is
 // the accent, with its handles: corners and a rotate knob, or a polygon's points.
 bool maskMode=C[34].x>.5;uint n=maskCount();int sel=(int)C[34].z-1,build=(int)C[34].w-1;
 float2 q=worldToScan(w);float pxs=C[0].z*canvasScale()/(2.5*extent_a);
 [loop]for(uint j=0;j<n;j++){
  float4 info=maskInfo(j),r=maskRect(j);bool on=info.z>.5,block=info.y<.5,picked=(int)j==sel;
  float d=maskDistance(j,q)*pxs;
  float3 ink=!on?IL_RULE:(block?IL_ALARM:IL_INK);
  if(on&&d<0){
   if(block)col=lerp(col,IL_ALARM,frac((px.x+px.y)/9)<.14?.35:.07);
   else col=lerp(col,IL_MID,.06);
  }
  col=lerp(col,picked?IL_ACCENT:ink,(1-smoothstep(.6,1.6,abs(d)))*(maskMode||!picked?1:.6));
  if(picked&&maskMode){
   if(info.x>1.5){
    uint np=polyCount(j);
    [loop]for(uint i=0;i<np;i++){float2 e=abs(px-screen(scanToWorld(polyPoint(j,i))));float m=max(e.x,e.y);
     if(m<4.5)col=m>3.5||(i==0&&(int)j==build)?IL_ACCENT:IL_FIELD;}
   }else{
    [unroll]for(uint c=0;c<4;c++){float2 e=abs(px-screen(scanToWorld(cornerOf(info,r,c))));float m=max(e.x,e.y);
     if(m<4.5)col=m>3.5?IL_ACCENT:IL_FIELD;}
    float2 top=screen(scanToWorld(r.xy+rot(float2(0,-r.w),info.w))),knob=screen(scanToWorld(knobOf(info,r,pxs)));
    col=lerp(col,IL_ACCENT,(1-smoothstep(.4,1.2,seg(px,top,knob)))*.7);
    float kd=length(px-knob);col=lerp(col,IL_ACCENT,1-smoothstep(.6,1.6,abs(kd-5)));
   }
  }
 }
 // The polygon being drawn: a rubber band from its last point to the pointer, and a ring on the
 // first point once clicking it would close the shape.
 if(maskMode&&build>=0&&build<(int)n&&polyCount(build)>0){
  if(polyCount(build)>=3){float rd=length(px-screen(scanToWorld(polyPoint(build,0))));col=lerp(col,IL_ACCENT,1-smoothstep(.6,1.6,abs(rd-11)));}
  float2 last=screen(scanToWorld(polyPoint(build,polyCount(build)-1))),ptr=_ViewportPointerPosition*_Resolution;
  if(seg(px,last,ptr)<.8&&frac(length(px-last)/8)<.5)col=IL_ACCENT;
 }
 // Margin: dashed, from the compiled Calibration (the enabled masks, margin already applied).
 uint cn=(uint)clamp(Calib[CAL_MASK_BASE].x,0,MASK_MAX);
 if(mask_margin>0)[loop]for(uint cj=0;cj<cn;cj++){
  float4 ci=Calib[CAL_MASK_BASE+1+2*cj],cr=Calib[CAL_MASK_BASE+2+2*cj];float de;
  if(ci.x>1.5){
   uint np=(uint)clamp(cr.x,0,POLY_MAX);de=1e9;
   [loop]for(uint i=0;i<np;i++)de=min(de,segDist(q,Calib[CAL_POLY_BASE+POLY_MAX*cj+i].xy,Calib[CAL_POLY_BASE+POLY_MAX*cj+(i+1)%np].xy));
  }else{float2 l=rot(q-cr.xy,-ci.w);
   if(ci.x<.5){float2 e=abs(l)-cr.zw;de=abs(length(max(e,0))+min(max(e.x,e.y),0));}
   else{float2 h=max(cr.zw,1e-6);de=abs((length(l/h)-1)*min(h.x,h.y));}}
  if(de*pxs<.8&&frac((px.x-px.y)/10)<.5)col=lerp(col,ci.y<.5?IL_ALARM:IL_INK,.7);
 }
 [unroll]for(int k=0;k<25;k++){
  bool corner=k==0||k==4||k==20||k==24,selected=C[8+k].x>.5;
  float2 delta=px-screen(controlPoint(k));float d=length(delta),radius=corner?11:6;
  float3 ink=maskMode?IL_DIM:(selected?IL_ACCENT:IL_INK);
  col=lerp(col,ink*.28,(1-smoothstep(radius-1,radius,d))*(selected?1:0));
  col=lerp(col,ink,1-smoothstep(.7,1.7,abs(d-radius)));
  if(corner&&d<radius*.55)col=lerp(col,ink,1-smoothstep(.5,1.5,min(abs(delta.x),abs(delta.y))));
 }
 if(C[2].x==2){
  float2 v0=screen(min(C[1].xy,C[1].zw)),v1=screen(max(C[1].xy,C[1].zw));
  if(all(px>=v0)&&all(px<=v1)){
   col=lerp(col,IL_MID,.18);
   if(min(min(px.x-v0.x,v1.x-px.x),min(px.y-v0.y,v1.y-px.y))<1.5)col=IL_INK;
  }
 }
 OutputUAV[id.xy]=float4(col,1);
}
