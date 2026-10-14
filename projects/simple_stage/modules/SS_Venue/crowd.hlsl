// The club crowd on a jittered CROWD_PITCH grid from the barrier back: densest at the barrier, thinning towards the
// bar, kept clear of the front-of-house riser and the walls. Deterministic by seed. p=(x, floor, z, height)
// look=(facing radians, left arm 0-1, right arm 0-1, bob phase); height 0 = empty.
#include "venue_view.hlsli"
struct Person{float4 p;float4 look;};RWStructuredBuffer<Person> C:register(u0);
float h1(float2 q){return frac(sin(dot(q,float2(127.1,311.7))+crowd_seed*17.13)*43758.5453);}
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=PV_PEOPLE)return;Person o=(Person)0;
 uint cx=i%CROWD_NX,cz=i/CROWD_NX;float2 q=float2(CROWD_X0+cx*CROWD_PITCH,CROWD_Z0+cz*CROWD_PITCH)+(float2(h1(float2(i,1)),h1(float2(i,2)))-.5)*.36;
 float zf=roomZ()+hall_length*.5,zh=lerp(CROWD_BARRIER,zf,.62);
 bool ok=crowd&&cz<CROWD_NZ&&abs(q.x)<hall_width*.5-.9&&q.y<zf-3.2;
 if(ok&&abs(q.x-2.6)<2.3&&abs(q.y-zh)<1.9)ok=false;                 // the front-of-house riser
 float depth=saturate((q.y-CROWD_BARRIER)/max(zf-3.2-CROWD_BARRIER,1));
 if(ok&&h1(float2(i,3))>crowd_density*lerp(1.0,.38,depth))ok=false;
 if(ok){float face=atan2(-q.x,-(q.y-.5))+(h1(float2(i,4))-.5)*.7;float hands=h1(float2(i,5));
  float l=hands<.22?1:hands<.38?.55:0,r=hands<.12?1:(hands>.8?.8:0);
  o.p=float4(q.x,floor_level,q.y,1.58+h1(float2(i,6))*.34);o.look=float4(face,l,r,h1(float2(i,7)));}
 C[i]=o;}
