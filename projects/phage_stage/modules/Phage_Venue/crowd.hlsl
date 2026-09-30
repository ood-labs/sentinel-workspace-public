// A packed crowd on a jittered 1.05 m grid: densest at the barrier, thinning to the back, parted
// around every spike foot (with swing clearance) and kept off the booth. Deterministic by seed.
// p=(x, 0, z, hall_height) look=(facing radians, left arm 0-1, right arm 0-1, bob phase); hall_height 0 = empty.
StructuredBuffer<float4> DesignIn:register(t0);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
struct Person{float4 p;float4 look;};RWStructuredBuffer<Person> C:register(u0);
float h1(float2 q){return frac(sin(dot(q,float2(127.1,311.7))+crowd_seed*17.13)*43758.5453);}
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=3072)return;Person o=(Person)0;
 uint cx=i%56,cz=i/56;float2 q=float2(-29.4+cx*1.05,-16+cz*1.05)+(float2(h1(float2(i,1)),h1(float2(i,2)))-.5)*.62;
 bool ok=crowd&&_Data0_Count>=17&&DesignIn[16].w==260929&&cz<55;
 if(ok){PhDesign D=phLoad();
  float barrier=D.riserD*.5+3.2;bool front=q.y>barrier;bool flank=abs(q.x)>D.plateR+5.5&&q.y>-14;
  ok=(front||flank)&&abs(q.x)<hall_width*.5-9.5&&q.y<hall_length*.5-11;
  for(uint l=0;l<6;l++){float3 a=phAnkleRest(D,l);if(length(q-a.xz)<3.4)ok=false;}
  float depth=max(0,q.y-barrier)/32.0;float keep=crowd_density*(front?lerp(1.0,.42,saturate(depth)):.55);
  if(h1(float2(i,3))>keep)ok=false;}
 if(ok){float face=atan2(-q.x,-(q.y-2))+(h1(float2(i,4))-.5)*.7;float hands=h1(float2(i,5));
  float l=hands<.22?1:hands<.38?.55:0,r=hands<.12?1:(hands>.8?.8:0);
  o.p=float4(q.x,floor_level,q.y,1.58+h1(float2(i,6))*.34);o.look=float4(face,l,r,h1(float2(i,7)));}
 C[i]=o;}
