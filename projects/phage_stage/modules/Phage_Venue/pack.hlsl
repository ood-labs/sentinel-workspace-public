// Packs room settings, bar emitters, architecture and crowd into the one Venue buffer.
// Each source keeps its own stride, so records are read typed and split into float4 rows.
#include "../_shared/phage_venue.hlsli"
struct RoomSettings{float4 fill,material,tint,bounds,finish;};
struct Emitter{float4 a,b,radiance;};
struct Architecture{float4 center,extent,surface,rotation;};
struct Person{float4 p;float4 look;};
StructuredBuffer<RoomSettings> RoomIn:register(t0);
StructuredBuffer<Emitter> EmitIn:register(t1);
StructuredBuffer<Architecture> ArchIn:register(t2);
StructuredBuffer<Person> CrowdIn:register(t3);
RWStructuredBuffer<float4> O:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=PV_COUNT)return;float4 v=0;
 if(i<5){RoomSettings r=RoomIn[0];v=i==0?r.fill:i==1?r.material:i==2?r.tint:i==3?r.bounds:r.finish;}
 else if(i==5)v=float4(PV_EMIT,PV_ARCH,PV_CROWD,260931);
 else if(i>=PV_EMIT&&i<PV_ARCH){uint k=i-PV_EMIT;Emitter e=EmitIn[k/3];uint f=k%3;v=f==0?e.a:f==1?e.b:e.radiance;}
 else if(i>=PV_ARCH&&i<PV_CROWD){uint k=i-PV_ARCH;Architecture a=ArchIn[k/4];uint f=k%4;v=f==0?a.center:f==1?a.extent:f==2?a.surface:a.rotation;}
 else if(i>=PV_CROWD){uint k=i-PV_CROWD;Person p=CrowdIn[k/2];v=k%2==0?p.p:p.look;}
 O[i]=v;}
