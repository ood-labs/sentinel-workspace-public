#include "../_shared/room_materials.hlsli"
#include "surface_lights.hlsli"
struct Architecture{float4 center,extent,surface,rotation;};StructuredBuffer<Architecture>A:register(t0);
struct V{float4 pos:SV_POSITION;float3 world:TEXCOORD0;float3 normal:TEXCOORD1;float4 surface:TEXCOORD2;float mat:TEXCOORD3;};
V VSMain(uint id:SV_VertexID){V o=(V)0;Architecture a=A[id/36];if(a.extent.w<.5){o.pos=float4(0,0,-2,1);return o;}uint f=(id%36)/6,k=id%6;float2 uv=float2(k==1||k==4||k==5?1:-1,k==2||k==3||k==5?1:-1);float s=f%2==0?-1:1;float3 q;
if(f<2){q=float3(s,uv);o.normal=float3(s,0,0);}else if(f<4){q=float3(uv.x,s,uv.y);o.normal=float3(0,s,0);}else{q=float3(uv,s);o.normal=float3(0,0,s);}float3 local=q*a.extent.xyz;float cs=cos(a.rotation.x),sn=sin(a.rotation.x);local.xy=float2(cs*local.x-sn*local.y,sn*local.x+cs*local.y);o.normal.xy=float2(cs*o.normal.x-sn*o.normal.y,sn*o.normal.x+cs*o.normal.y);o.world=a.center.xyz+local;o.surface=a.surface;o.mat=a.center.w;o.pos=mul(_ViewProjMatrix,float4(o.world,1));return o;}
float4 PSMain(V i):SV_TARGET{
 float3 n=normalize(i.normal),v=normalize(_CameraPos-i.world);if(dot(n,v)<0)n=-n;
 RoomSettings room=Room[0];float3 p=i.world;float2 uv=abs(n.y)>.5?p.xz:abs(n.x)>.5?p.zy:p.xy;
 float coarse=roomNoise(uv*.33),patch=roomNoise(uv*1.7),fine=roomNoise(uv*11);
 float detail=saturate(1-length(fwidth(uv))*8);float variation=(coarse-.5)*.32+(patch-.5)*.13+(fine-.5)*.055*detail;
 float rough=.83,metal=0;float3 albedo=i.surface.rgb*(.7+variation*room.finish.y);
 if(i.mat<.5){
  float wear=roomNoise(uv*.21+13)*roomNoise(uv*.7);rough=clamp(room.material.z+(wear-.4)*room.finish.x*.3,.12,1);
  albedo=float3(.09,.087,.08)*(1+variation*room.finish.x);
  float2 joints=abs(frac(uv/5+.5)-.5)*5;float seam=1-smoothstep(.006,.018+max(fwidth(uv.x),fwidth(uv.y)),min(joints.x,joints.y));albedo*=1-.4*seam;
  n=normalize(n+float3(ddx(fine)*.07,0,ddy(fine)*.07)*detail);
 }else if(i.mat>1.5&&i.mat<2.5){albedo=float3(.035,.038,.042);metal=.65;rough=.48;}
 else{
  // Cast concrete lift lines and subtle streaks, rather than uniform flat grey.
  float form=1-smoothstep(.008,.022+fwidth(uv.y),abs(frac(uv.y/2.4+.5)-.5)*2.4);
  float runoff=roomNoise(float2(uv.x*3,uv.y*.16));albedo*=1-room.finish.y*(form*.18+runoff*.12);
 }
 float hemi=.2+.8*saturate(dot(n,normalize(float3(-.3,1,.2))));
 float footing=smoothstep(.0,.65,p.y-room.bounds.w);if(abs(n.y)<.5)albedo*=lerp(.6,1,footing);
 float3 c=albedo*room.fill.x*room.tint.rgb*hemi;
 c+=fixtureMaterial(p,n,v,albedo,rough,metal)+roomLEDLight(p,n,v,albedo,rough,metal);
 return float4(c,length(_CameraPos-p));}
