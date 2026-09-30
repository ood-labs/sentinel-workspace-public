// Joint boxes, spike cones, riser, DJ table and the DJ, lit like the rest of the rig.
#include "../_shared/room_materials.hlsli"
#include "surface_lights.hlsli"
struct PhSolid{float4 c;float4 x;float4 y;float4 z;};StructuredBuffer<PhSolid> S:register(t0); // Structure buffer: solids follow the 13248 tubes
struct V{float4 pos:SV_POSITION;float3 world:TEXCOORD0;float3 normal:TEXCOORD1;float mat:TEXCOORD2;};
float3 boxCorner(uint v,out float3 n){uint f=v/6,k=v%6;float2 uv=float2(k==1||k==4||k==5?1:-1,k==2||k==3||k==5?1:-1);float s=f%2==0?-1:1;
 if(f<2){n=float3(s,0,0);return float3(s,uv);}if(f<4){n=float3(0,s,0);return float3(uv.x,s,uv.y);}n=float3(0,0,s);return float3(uv,s);}
V VSMain(uint id:SV_VertexID){V o=(V)0;uint si=id/216,v=id%216;o.pos=float4(0,0,-1,1);
 if(si>=64||13248+si>=_Data3_Count)return o;PhSolid s=S[13248+si];uint kind=(uint)s.c.w%10;if(kind==0)return o;o.mat=floor(s.c.w/10);
 float3 X=s.x.xyz,Y=s.y.xyz,Z=s.z.xyz,p,n;
 if(kind==1){if(v>=36)return o;float3 q=boxCorner(v,n);p=s.c.xyz+X*q.x*s.x.w+Y*q.y*s.y.w+Z*q.z*s.z.w;n=X*n.x+Y*n.y+Z*n.z;}
 else if(kind==2){if(v>=144)return o;uint seg=v/6,c=v%6;float a0=seg*6.2831853/24,a1=(seg+1)*6.2831853/24;
  float3 r0=X*cos(a0)+Z*sin(a0),r1=X*cos(a1)+Z*sin(a1);float3 tip=s.c.xyz+Y*s.y.w;
  if(c<3){p=c==0?s.c.xyz+r0*s.x.w:c==1?s.c.xyz+r1*s.x.w:tip;float3 m=normalize(r0+r1);n=normalize(m*s.y.w+Y*s.x.w);}
  else{p=c==3?s.c.xyz:c==4?s.c.xyz+r1*s.x.w:s.c.xyz+r0*s.x.w;n=-Y;}}
 else{uint b=v/36;if(b>=5)return o;float H=s.y.w;float3 cen,half_;
  if(b==0){cen=float3(0,.24*H,0);half_=float3(.16,.24*H,.1);}else if(b==1){cen=float3(0,.62*H,0);half_=float3(.21,.15*H,.12);}
  else if(b==2){cen=float3(0,.87*H,0);half_=float3(.1,.065*H,.11);}else{float sd=b==3?-1:1;cen=float3(sd*.24,.7*H,.2);half_=float3(.055,.055,.24);}
  float3 q=boxCorner(v%36,n);float3 lp=cen+q*half_;p=s.c.xyz+X*lp.x+Y*lp.y+Z*lp.z;n=X*n.x+Y*n.y+Z*n.z;}
 o.world=p;o.normal=n;o.pos=mul(_ViewProjMatrix,float4(p,1));return o;}
float4 PSMain(V i):SV_TARGET0{
 float3 n=normalize(i.normal),v=normalize(_CameraPos-i.world);if(dot(n,v)<0)n=-n;RoomSettings room=roomSettings();
 float3 albedo=float3(.8,.82,.85);float rough=room.material.x,metal=1;
 if(i.mat>.5&&i.mat<1.5){albedo=float3(.03,.032,.036);rough=.28;metal=.8;}
 else if(i.mat>1.5&&i.mat<2.5){albedo=float3(.018,.018,.02);rough=.7;metal=0;}
 else if(i.mat>2.5){albedo=float3(.03,.028,.027);rough=.9;metal=0;}
 float3 c=albedo*(.02+.06*saturate(dot(n,normalize(float3(-.3,1,.4)))))*worklight;
 c+=phageLight(i.world,n,v,albedo,rough,metal);
 return float4(c,length(i.world-_CameraPos));}
