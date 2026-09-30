// Truss tubes: 12-sided cylinders, polished aluminium lit by beams, strobes and the pixel bars.
#include "../_shared/room_materials.hlsli"
#include "surface_lights.hlsli"
struct Tube{float4 a;float4 b;float4 cutA;float4 cutB;};StructuredBuffer<Tube>T:register(t0);
struct V{float4 pos:SV_POSITION;float3 world:TEXCOORD0;float3 normal:TEXCOORD1;float mat:TEXCOORD2;};
V VSMain(uint id:SV_VertexID){V o=(V)0;uint tube=id/72,v=id%72;
 if(tube>=13248||tube>=_Data3_Count){o.pos=float4(0,0,-1,1);return o;}
 Tube t=T[tube];if(t.a.w<=0){o.pos=float4(0,0,-1,1);return o;}
 uint side=v/6,k=v%6;uint corners[6]={0,1,2,2,1,3};uint c=corners[k];float3 d=normalize(t.b.xyz-t.a.xyz),u=normalize(cross(abs(d.y)<.9?float3(0,1,0):float3(1,0,0),d)),vv=cross(d,u);
 float a=6.2831853*(side+(c%2))/12;float3 n=cos(a)*u+sin(a)*vv;float3 p=(c<2?t.a.xyz:t.b.xyz)+n*t.a.w;
 o.mat=t.b.w;o.world=p;o.normal=n;o.pos=mul(_ViewProjMatrix,float4(p,1));return o;}
float4 PSMain(V i):SV_TARGET0{
 float3 n=normalize(i.normal),v=normalize(_CameraPos-i.world);if(dot(n,v)<0)n=-n;
 RoomSettings room=roomSettings();float rough=room.material.x,metal=1;float3 albedo=float3(.86,.88,.9);
 if(i.mat>.5){albedo=float3(.05,.052,.056);rough=.55;metal=.4;}
 float3 reflection=reflect(-v,n);float ceiling=smoothstep(-.4,.65,reflection.y);
 float3 environment=lerp(float3(.03,.033,.042),float3(.42,.46,.55),ceiling);
 float3 F=roomFresnel(saturate(dot(n,v)),lerp(.04.xxx,albedo,metal));
 float3 c=environment*F*room.fill.z*room.material.y+(.012+.05*pow(saturate(dot(reflect(-normalize(float3(-.5,.8,-.6)),n),v)),24))*worklight*albedo;
 c+=phageLight(i.world,n,v,albedo,rough,metal)*room.material.y;
 return float4(c,length(i.world-_CameraPos));}
