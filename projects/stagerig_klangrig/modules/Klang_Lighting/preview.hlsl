
#include "../_shared/rm_types.hlsli"
#include "../_shared/rig.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "map.hlsli"
#include "groups.hlsli"
StructuredBuffer<RmOptical>O:register(t0);StructuredBuffer<RmPose>P:register(t1);StructuredBuffer<RigRecord>R:register(t2);StructuredBuffer<float4>S:register(t3);RWTexture2D<float4>OutputUAV:register(u0);
float lineDist(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),.001)));}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;float2 p=id.xy+.5;float3 c=float3(.025,.035,.05);float4 bounds=S[3];
 for(uint j=0;j<49;j++){RigRecord r=R[j];float d=lineDist(p,mapPoint(r.a.xyz,bounds),mapPoint(r.b.xyz,bounds));c=lerp(c,j==0?float3(.42,.4,.3):float3(.17,.23,.28),1-smoothstep(1,2,d));}
 for(uint f=0;f<288;f++){RmPose r=P[f];if(r.active<.5||!visible(f))continue;float2 q=marker(r.position,f,bounds);float d=length(p-q);if(d>14)continue;float selected=S[4+f].x;float3 ink=selected>.5?float3(1,.8,.35):float3(.32,.45,.55);c=lerp(c,ink,(1-smoothstep(9,10,d))*smoothstep(7.5,8.5,d));RmOptical lens=O[f*25],ring=O[f*25+1];float3 rgb=d>4?ring.colour*ring.intensity:lens.colour*lens.intensity;c=lerp(c,.06+1-exp(-rgb),1-smoothstep(5.5,6.5,d));}
 if(S[0].x>0&&length(S[1].xy-S[1].zw)>3){float2 lo=min(S[1].xy,S[1].zw),hi=max(S[1].xy,S[1].zw);if(all(p>=lo)&&all(p<=hi)){float edge=min(min(p.x-lo.x,hi.x-p.x),min(p.y-lo.y,hi.y-p.y));c=lerp(c,float3(.85,.72,.38),edge<1.5?.85:.08);}}
 float t=sui3Text(p,float2(24,20),2,84,79,80,32,47,32,76,73,71,72,84,83);t=max(t,sui3Digits(p,float2(w-110,20),2,(int)S[0].z,3));c=lerp(c,float3(.85,.88,.9),t);
 c=groupButtons(p,c);OutputUAV[id.xy]=float4(c,1);}
