#include "../_shared/program.hlsli"
StructuredBuffer<KlangProgram>Program:register(t4);
#include "../_shared/rm_types.hlsli"
StructuredBuffer<RmPose> Poses:register(t0);
StructuredBuffer<float4>Selected:register(t1);
#include "../_shared/rig.hlsli"
#include "../_shared/show.hlsli"
StructuredBuffer<float4>Show:register(t2);StructuredBuffer<RigRecord>Rig:register(t3);
RWStructuredBuffer<RmOptical> Optics:register(u0);
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint i=tid.x;if(i>=7200)return;uint parent=i/25,k=i%25;RmPose r=Poses[parent];RmOptical o=(RmOptical)0;
 if(r.active>.5){
  bool ring=k>0;float2 uv=r.content_origin+r.content_extent*float2(ring?(k-1+.5)/24:.5,.5);
  o.colour=ring?ring_color:main_color;
  uint group=(parent<64||parent>=256)?0:1+(parent-64)/16;float gate=(isolate_group<0||group==(uint)isolate_group)?1:0;
  if(_Data2_Count>=3&&Show[0].y>.5&&Show[2].x<.5&&_Data1_Count>=49){float rank=klangRank(r.position.z,Rig[0].a.z,Rig[0].b.z,Show[1].y);gate*=klangPulse(Show[0].x,rank,Show[0].z,Show[0].w);}
  o.intensity=gate*(solo_selected?Selected[4+parent].x:1)*dimmer*exp2(boost)*(ring?ring_master*.2:main_master*8);
  if(_Data3_Count>=289&&_Data2_Count>=9&&Show[2].x>.5){KlangProgram pr=Program[parent];float rank=klangRank(r.position.z,Rig[0].a.z,Rig[0].b.z,pr.timing.z);
 uint color=(uint)(ring?pr.routing.y:pr.routing.x);o.colour=Show[6+min(2u,color)].rgb;
 uint lane=(uint)pr.routing.w;uint fx=klangMoverFx(pr.timing.w);float intensity=1;if(lane>0){float4 l=Show[2+min(3u,lane)];float p=(l.x+pr.timing.y)*exp2((float)(fx&3));intensity=l.y*klangPulse(p,rank,pr.timing.x,pr.movement.w);
 if(fx&4){float n=floor(p-saturate(rank)*pr.movement.w);intensity*=klangHash(float3(parent,fmod(l.z,997),n))<.34?1:0;}}
 uint cl=(uint)pr.movement.x;if(cl>0){float4 l=Show[2+min(3u,cl)];o.colour=lerp(o.colour,Show[6+(color+1)%3].rgb,l.y*(.5+.5*sin((l.x+pr.timing.y-rank*pr.movement.w)*6.2831853)));}
 float localLevel=ring?pr.aim.w:pr.aim.z;
 if(_Data2_Count>=10&&Show[9].x>.5){o.colour=1;intensity=Show[9].y;localLevel=1;}
 o.intensity*=intensity*localLevel*pr.meta.y;}
  float a=(k-1.0)*6.2831853/24;float3 local=ring?float3(sin(a)*.086,cos(a)*.086,-.074):float3(0,0,-.070);
  o.position=rmHeadPoint(local,r);o.normal=rmHeadNormal(float3(0,0,-1),r);o.fixture_id=r.fixture_id;o.local_id=ring?k-1:0;o.active=1;
  o.beam_tangent=tan(radians(ring?55:1.5));o.field_tangent=tan(radians(ring?80:2.2));o.reach=reach;o.padding.x=ring?1:0;
 }Optics[i]=o;
}
