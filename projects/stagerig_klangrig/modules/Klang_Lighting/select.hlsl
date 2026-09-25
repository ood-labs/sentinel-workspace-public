
#include "map.hlsli"
#include "group_layout.hlsli"
RWStructuredBuffer<float4>S:register(u0);
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 if(_Data0_Count<288||_Data1_Count<49||_Data1[0].a.w<.5||_Data0[0].base_visible<.5)return;
 if(S[0].w!=260927){for(uint i=0;i<311;i++)S[i]=0;S[0].w=260927;for(uint f=0;f<288;f++)S[4+f].x=0;}
 bool localChange=false;
float words[18]={remote_selection0,remote_selection1,remote_selection2,remote_selection3,remote_selection4,remote_selection5,remote_selection6,remote_selection7,remote_selection8,remote_selection9,remote_selection10,remote_selection11,remote_selection12,remote_selection13,remote_selection14,remote_selection15,remote_selection16,remote_selection17};if(S[2].z!=selection_apply){for(uint f=0;f<288;f++)S[4+f].x=((uint)words[f/16]>>(f%16))&1;S[2].z=selection_apply;}
 float4 bounds=float4(1e5,-1e5,1e5,-1e5);for(uint i=0;i<49;i++){float3 a=_Data1[i].a.xyz,b=_Data1[i].b.xyz;bounds.x=min(bounds.x,min(a.z,b.z));bounds.y=max(bounds.y,max(a.z,b.z));bounds.z=min(bounds.z,min(a.x,b.x));bounds.w=max(bounds.w,max(a.x,b.x));}S[3]=bounds;
 if(_ViewportEventCount>0&&_ViewportEvents[min((uint)_ViewportEventCount,64u)-1].sequence<S[2].x)S[2].x=0;
 for(uint k=0;k<min((uint)_ViewportEventCount,64u);k++){ViewportEvent e=_ViewportEvents[k];
 if(e.sequence<=S[2].x)continue;S[2].x=e.sequence;
 if(e.type==2&&e.phase==1&&e.position.y<.20){
  S[0].x=0;for(uint button=0;button<16;button++){float4 r=groupRect(button);
   if(all(e.position>=r.xy)&&all(e.position<=r.zw)){S[310].x=button+1;S[310].y+=1;}}
  continue;
 }
 if(e.position.y<.20&&S[0].x<.5&&e.type!=4)continue;if(e.type==4||e.type==2||(e.type==5&&e.code==3))localChange=true;float2 px=e.position*_Resolution;
 if(e.type==4&&e.phase==1&&(e.code==1||e.code==48)){for(uint f=0;f<288;f++)S[4+f].x=e.code==1?_Data0[f].active:0;S[0].x=0;}
 if(e.type==2&&e.phase==1&&e.code==0){S[0].x=1;S[0].y=e.modifiers;S[1]=float4(px,px);uint pick=999;float best=14;for(uint f=0;f<288;f++){S[4+f].y=S[4+f].x;if(_Data0[f].active>.5&&visible(f)){float d=length(px-marker(_Data0[f].position,f,bounds));if(d<best){best=d;pick=f;}}}
 for(uint f=0;f<288;f++){bool hit=f==pick;uint mods=(uint)S[0].y;S[4+f].x=(mods&2)?(hit?1-S[4+f].y:S[4+f].y):(mods&1)?max(S[4+f].y,hit?1:0):(hit?1:0);}}
 if(e.type==5&&e.code==3&&S[0].x>0){if(e.phase==8){for(uint f=0;f<288;f++)S[4+f].x=S[4+f].y;S[0].x=0;}
 else if(e.phase==6||e.phase==7){S[1].zw=px;float2 lo=min(S[1].xy,px),hi=max(S[1].xy,px);for(uint f=0;f<288;f++){float2 p=marker(_Data0[f].position,f,bounds);bool hit=all(p>=lo)&&all(p<=hi)&&_Data0[f].active>.5&&visible(f);uint mods=(uint)S[0].y;S[4+f].x=(mods&2)?(hit?1-S[4+f].y:S[4+f].y):(mods&1)?max(S[4+f].y,hit?1:0):(hit?1:0);}if(e.phase==7)S[0].x=0;}}
 if(e.type==2&&e.phase==2)S[0].x=0;
 }
 if(localChange)S[2].w+=1;for(uint w=0;w<18;w++){uint bits=0;for(uint b=0;b<16;b++)if(S[4+w*16+b].x>.5)bits|=1u<<b;S[292+w]=float4(bits,0,0,0);}
 S[0].z=remote_led_selection?1:0;for(uint f=0;f<288;f++){S[0].z+=_Data0[f].active>.5?S[4+f].x:0;}
}
