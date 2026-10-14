// Editor state: E[0]=(selected leg+1, drag kind 1 foot/2 knee, dragging, magic),
// E[1]=edit at drag start, E[2]=pointer at drag start, E[3]=(symmetry, last event sequence),
// E[4..9]=per-leg edits (foot radial, foot tangential, knee radial, knee height).
RWStructuredBuffer<float4> E:register(u0);
#include "plan_design.hlsli"
#include "../_shared/phage_anatomy.hlsli"
#include "layout.hlsli"
#include "pick.hlsli"
float4 clampEdit(float4 v){return float4(clamp(v.x,-6,6),clamp(v.y,-5,5),clamp(v.z,-5,5),clamp(v.w,-5,6));}
void writeLeg(uint i,float4 v,bool sym){
 v=clampEdit(v);E[4+i]=v;
 if(sym){uint m=mirrorLeg(i);E[4+m]=float4(v.x,-v.y,v.z,v.w);}
}
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 if(E[0].w!=PLAN_MAGIC){for(uint k=0;k<16;k++)E[k]=0;E[0]=float4(1,0,0,PLAN_MAGIC);E[3]=float4(1,0,0,0);}
 PhDesign D=phLoad();PhPose R=phRest();
 // The saved watermark outlives the host's per-node event counter, which restarts at 1 when the
 // node is recreated (project load, app restart). A ring that tops out below it means a restart.
 uint n=min((uint)_ViewportEventCount,64u);float ringMax=0;
 for(uint r=0;r<n;r++)ringMax=max(ringMax,(float)_ViewportEvents[r].sequence);
 if(n>0&&ringMax<E[3].y)E[3].y=0;
 for(uint k=0;k<n;k++){
  ViewportEvent e=_ViewportEvents[k];float seq=(float)e.sequence;
  if(seq<=E[3].y&&seq>E[3].y-4096)continue;E[3].y=seq;
  float2 px=e.position*_Resolution;int sel=(int)E[0].x-1;bool sym=E[3].x>.5;
  if(e.type==4&&e.phase==1){
   if(e.code==48)E[0].x=0;
   else if(e.code==19)E[3].x=sym?0:1;
   else if(e.code==18&&sel>=0){E[4+sel]=0;if(sym)E[4+mirrorLeg((uint)sel)]=0;}
   else if(e.code>=33&&e.code<=38)E[0].x=e.code-32;
  }
  if(e.type==2&&e.phase==1&&e.code==0){
   int2 pk=planPick(px,sel,D,R);int pick=pk.x;float kind=(float)pk.y;
   if(pick>=0){E[0].x=pick+1;E[0].y=kind;E[0].z=kind>0?1:0;E[1]=E[4+pick];E[2]=float4(px,0,0);}
  }
  if(E[0].z>.5&&E[0].x>0&&((e.type==5&&e.code==3&&(e.phase==6||e.phase==7))||(e.type==1&&ViewportButtonDown(0)))){
   uint i=(uint)E[0].x-1;float4 v=E[1];
   if(E[0].y<1.5){float2 d=(px-E[2].xy)/planScale();float3 w=float3(d.x,0,d.y);float az=phLegAz(i);
    v.x+=dot(w,phDir(az));v.y+=dot(w,phTan(az));}
   else{float2 d=(px-E[2].xy)/sectScale();v.z+=d.x;v.w-=d.y;}
   writeLeg(i,v,sym);
  }
  if((e.type==5&&e.code==3&&(e.phase==7||e.phase==8))||(e.type==2&&e.phase==3))E[0].z=0;
 }
}
