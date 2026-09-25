
#include "layout.hlsli"
RWStructuredBuffer<float4>E:register(u0);
float3 editedHandle(uint h){if(h==0)return handle(0)+E[4].xyz;uint w=h-1;float3 pivot=wingPoint(w,0),d=wingPoint(w,1)-pivot;float a=radians(wing_angle)*(w%2==0?-1:1);d.xy=float2(cos(a)*d.x-sin(a)*d.y,sin(a)*d.x+cos(a)*d.y);return pivot+d+E[4+h].xyz+E[4].xyz;}
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 if(E[0].w!=260922){for(uint i=0;i<17;i++)E[i]=0;E[0]=float4(0,0,0,260922);}
 for(uint k=0;k<min((uint)_ViewportEventCount,64u);k++){
 ViewportEvent e=_ViewportEvents[k];float2 px=e.position*_Resolution;uint v=viewAt(px);
 if(e.type==4&&e.phase==1&&e.code==18&&E[0].x>0)E[3+(uint)E[0].x]=0;
 if(e.type==2&&e.phase==2&&e.code==0)E[0].z=0;
 if(e.type==4&&e.phase==1&&e.code==48&&E[0].x>0&&E[0].z>0){E[3+(uint)E[0].x]=E[1];E[0].z=0;}
 if(e.type==2&&e.phase==1&&e.code==0){float best=18;uint pick=0;for(uint h=0;h<13;h++){float d=length(px-project(editedHandle(h),v));if(d<best){best=d;pick=h+1;}}
 E[0].xyz=float3(pick,v,pick>0?1:0);if(pick>0){E[1]=E[3+pick];E[2]=float4(px,0,0);}}
 if(e.type==5&&e.code==3&&E[0].x>0&&E[0].z>0){uint n=3+(uint)E[0].x;v=(uint)E[0].y;
 if(e.phase==8){E[n]=E[1];E[0].z=0;}
 else if(e.phase==6||e.phase==7){float2 d=(px-E[2].xy)/scaleAt(v);float3 shift=v==0?float3(d.y,0,-d.x):v==1?float3(0,-d.y,-d.x):float3(d.x,-d.y,0);E[n].xyz=E[1].xyz+shift;if(e.phase==7)E[0].z=0;}}
 }
}
