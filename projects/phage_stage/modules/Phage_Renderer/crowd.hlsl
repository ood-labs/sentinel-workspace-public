// The crowd: five boxes per person (legs, torso, head, two arms), arms raised per record, a small
// bounce locked to the conductor beat. Near-black cloth, so they read as silhouettes against haze.
#include "../_shared/room_materials.hlsli"
#include "surface_lights.hlsli"
struct Person{float4 p;float4 look;};
StructuredBuffer<float4> Show:register(t4);
struct V{float4 pos:SV_POSITION;float3 world:TEXCOORD0;float3 normal:TEXCOORD1;float skin:TEXCOORD2;};
float3 boxCorner(uint v,out float3 n){uint f=v/6,k=v%6;float2 uv=float2(k==1||k==4||k==5?1:-1,k==2||k==3||k==5?1:-1);float s=f%2==0?-1:1;
 if(f<2){n=float3(s,0,0);return float3(s,uv);}if(f<4){n=float3(0,s,0);return float3(uv.x,s,uv.y);}n=float3(0,0,s);return float3(uv,s);}
V VSMain(uint id:SV_VertexID){V o=(V)0;o.pos=float4(0,0,-1,1);uint pi=id/180,v=id%180;if(pi>=PV_PEOPLE||PV_CROWD+2*pi+1>=_Data4_Count)return o;
 Person r;r.p=Venue[PV_CROWD+2*pi];r.look=Venue[PV_CROWD+2*pi+1];if(r.p.w<.1)return o;float H=r.p.w;uint b=v/36;float3 n;float3 q=boxCorner(v%36,n);
 float beat=_Data5_Count>=3?Show[2].y:_Time*2.1;float bob=.07*crowd_bob*pow(abs(sin(3.14159*(beat+r.look.w*.25))),3);
 float3 cen,hx,hy,hz;hx=float3(1,0,0);hy=float3(0,1,0);hz=float3(0,0,1);float3 half_;
 if(b==0){cen=float3(0,.24*H,0);half_=float3(.15,.24*H,.1);}
 else if(b==1){cen=float3(0,.62*H,0);half_=float3(.2,.15*H,.11);}
 else if(b==2){cen=float3(0,.87*H,0);half_=float3(.095,.065*H,.1);o.skin=1;}
 else{float sd=b==3?-1:1;float raise=b==3?r.look.y:r.look.z;float a=lerp(.08,.93,raise)*3.14159;
  float3 dir=normalize(float3(sd*sin(a)*.42,-cos(a),sin(a)*.18));float len=.34*H;float3 sh=float3(sd*.2,.76*H,0);
  cen=sh+dir*len*.5;hy=dir;hx=normalize(cross(float3(0,0,1),hy));if(dot(hx,hx)<.1)hx=float3(1,0,0);hz=cross(hx,hy);half_=float3(.05,len*.5,.05);o.skin=raise>.5?.5:0;}
 float3 lp=cen+hx*q.x*half_.x+hy*q.y*half_.y+hz*q.z*half_.z;float3 ln=hx*n.x+hy*n.y+hz*n.z;
 float s=sin(r.look.x),c=cos(r.look.x);float3 wp=float3(c*lp.x+s*lp.z,lp.y+bob,-s*lp.x+c*lp.z)+r.p.xyz;float3 wn=float3(c*ln.x+s*ln.z,ln.y,-s*ln.x+c*ln.z);
 o.world=wp;o.normal=wn;o.pos=mul(_ViewProjMatrix,float4(wp,1));return o;}
float4 PSMain(V i):SV_TARGET0{
 float3 n=normalize(i.normal),v=normalize(_CameraPos-i.world);if(dot(n,v)<0)n=-n;RoomSettings room=roomSettings();
 float3 albedo=lerp(float3(.022,.021,.024),float3(.12,.085,.07),i.skin);
 float3 c=albedo*room.fill.y*room.tint.rgb*(.4+.6*saturate(n.y));
 c+=phageLightDiffuse(i.world,n,albedo);
 return float4(c,length(i.world-_CameraPos));}
