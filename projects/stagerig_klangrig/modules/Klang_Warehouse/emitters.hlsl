#include "../_shared/rig.hlsli"
StructuredBuffer<RigRecord> R:register(t0);Texture2D<float4> LED:register(t1);
struct Emitter{float4 a,b,radiance;};RWStructuredBuffer<Emitter> O:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=48)return;uint wing=i/4,edge=i%4;RigRecord r=R[i+1];float prior=0,total=0;float3 center=0;
for(uint j=0;j<4;j++){RigRecord q=R[1+wing*4+j];float len=sqrt(dot(q.b.xyz-q.a.xyz,q.b.xyz-q.a.xyz));if(j<edge)prior+=len;total+=len;center+=q.a.xyz*.25;}
float3 dir=normalize(r.b.xyz-r.a.xyz),inward=center-r.a.xyz;inward=normalize(inward-dir*dot(inward,dir));Emitter e;e.a=float4(r.a.xyz+inward*(r.shape.x*.5+.05),r.shape.y);e.b=float4(r.b.xyz+inward*(r.shape.x*.5+.05),1);float u=(prior+.5*sqrt(dot(r.b.xyz-r.a.xyz,r.b.xyz-r.a.xyz)))/max(total,.001);float3 radiance=0;[unroll]for(uint sample=0;sample<16;sample++)radiance+=LED.SampleLevel(LinearSampler,float2(u,(wing+(sample+.5)/16)/12),0).rgb/16;e.radiance=float4(radiance,1);O[i]=e;}
