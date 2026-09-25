#include "../_shared/program.hlsli"
StructuredBuffer<KlangProgram>Program:register(t2);
#include "../_shared/rm_types.hlsli"
#include "../_shared/rig.hlsli"
#include "../_shared/show.hlsli"
StructuredBuffer<RigRecord>Rig:register(t3);
StructuredBuffer<float4>Show:register(t1);
RWStructuredBuffer<RmPose> Poses:register(u0);
float moveToward(float value,float target,float step){return value+clamp(target-value,-step,step);}
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint i=tid.x;if(i>=288)return;RmPlan p=_Data0[i];RmPose r=Poses[i];
 if(i>=_Data0_Count||p.active<.5){r.active=0;Poses[i]=r;return;}
 if(r.reserved.w!=1||r.active<.5){r=(RmPose)0;r.reserved.w=1;}
 r.position=p.position;r.fixture_id=p.fixture_id;r.mount_pitch=p.mount_pitch;r.mount_roll=p.mount_roll;r.active=p.active;
 r.content_origin=p.content_origin;r.content_extent=p.content_extent;r.motion_mode=pan_mode+2*tilt_mode;r.reserved.z=p.base_visible;
 float4 input=0;
 // Alpha is validity: normal RG control textures use alpha1; an unbound SRV reads zero.
 bool useTexture=texture_enabled&&input.a>.5;float2 rg=saturate(input.rg);
 float2 target=useTexture?float2(lerp(pan_min,pan_max,rg.x),lerp(tilt_min,tilt_max,rg.y)):float2(manual_pan,manual_tilt);
 if(animate){target.x+=sin(r.reserved.x*rate*6.2831853+p.reserved.z*.13)*sweep;target.y+=cos(r.reserved.x*rate*6.2831853+p.reserved.z*.13)*sweep*.3;} target=clamp(target,float2(-270,-135),float2(270,135));
 bool referenceShow=_Data2_Count>=3&&Show[0].y>.5;
 if(referenceShow){float3 world;if(i<64||i>=256){world=float3(((uint)p.reserved.z%2)==0?-1:1,0,0);}else{uint wing=(i-64)/16;float side=p.reserved.w;float elev=radians(Show[1].x)*(wing%4<2?1:-1);world=float3(side*cos(elev),sin(elev),0);}float3 q=rmX(rmZ(world,-p.mount_roll),-p.mount_pitch);target=degrees(float2(atan2(-q.x,-q.z),asin(clamp(q.y,-1,1))));}
 if(_Data3_Count>=289&&_Data2_Count>=9&&Show[2].x>.5){KlangProgram pr=Program[i];target+=pr.aim.xy+float2(0,pr.meta.z);uint lane=(uint)pr.routing.z;
 if(lane>0){float4 l=Show[2+min(3u,lane)];float rank=saturate((p.position.z-min(Rig[0].a.z,Rig[0].b.z))/max(.001,abs(Rig[0].b.z-Rig[0].a.z)));if(pr.timing.z>.5)rank=1-rank;float ph=l.x-rank*pr.movement.w+pr.timing.y;uint fxm=klangMoverFx(pr.timing.w);if(fxm&16)target+=float2(pr.movement.y,pr.movement.z)*klangStepPoint(l.z,pr.timing.y,pr.timing.z);
 else if(fxm&8){float sd=fmod(l.z,997);target+=float2(pr.movement.y,pr.movement.z)*(float2(klangHash(float3(i,sd,1)),klangHash(float3(i,sd,2)))*2-1);}
 else target+=l.y*float2(pr.movement.y*sin(ph*6.2831853),pr.movement.z*cos(ph*6.2831853));}target=clamp(target,float2(-270,-135),float2(270,135));}
 float2 rotation=useTexture?rg*2-1:float2(manual_pan_rotation,manual_tilt_rotation);
 float dt=max(0,_DeltaTime);r.target_pan=radians(target.x);r.target_tilt=radians(target.y);
 r.pan=(referenceShow||pan_mode==0)?moveToward(r.pan,r.target_pan,radians(pan_speed)*dt):r.pan+radians(rotation.x*pan_speed)*dt;
 r.tilt=(referenceShow||tilt_mode==0)?moveToward(r.tilt,r.target_tilt,radians(tilt_speed)*dt):r.tilt+radians(rotation.y*tilt_speed)*dt;
 r.reserved.x+=dt;r.reserved.y=useTexture?1:0;Poses[i]=r;
}
