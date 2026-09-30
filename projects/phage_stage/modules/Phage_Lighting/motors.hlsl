// Mover motors. Programmer: pan/tilt from the program row (+ pitch) plus the lane's movement FX
// (circle, BUILD sweep, STEP, JUMP) or a continuous SPIN. Reference (no programmer): every family
// aims a designed default so the rig reads without a Surface. Eased toward target, speed-limited.
#include "lighting.hlsli"
StructuredBuffer<PhMount> Mounts:register(t0);
StructuredBuffer<float4> Show:register(t1);
StructuredBuffer<PhProgram> Program:register(t2);
StructuredBuffer<float4> Design:register(t3);
RWStructuredBuffer<PhMoverPose> Poses:register(u0);
bool programmer(){return _Data2_Count>=PH_SLOTS&&_Data1_Count>=PH_SHOW_COUNT&&Show[2].x>.5;}
// Reference aims: plate rows fan down over the crowd, the capsid and knees reach up, the collar
// throws out, the booth ring skims the floor and the feet lean back across the body.
float3 referenceAim(PhMount m){uint f=(uint)round(m.extra.x);float3 up=float3(0,1,0);float3 o=m.position;o.y=0;
 o=length(o)>1e-3?normalize(o):float3(0,0,1);float3 ov=-m.fwd;
 if(f<=1)return normalize(o*.55-up);
 if(f==2)return normalize(m.up+up*.9);
 if(f==3)return normalize(ov*.25+up);
 if(f==4)return normalize(o-up*.35);
 if(f==5)return normalize(o-up*.25);
 return normalize(-ov*.45+up);}
float wrap180(float a){return a-360*floor((a+180)/360);}
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=PH_MOVERS)return;
 PhMount m=Mounts[i];PhMoverPose r=Poses[i];
 if(i>=_Data0_Count||m.active<.5||m.kind!=0){Poses[i]=(PhMoverPose)0;return;}
 bool fresh=r.active<.5;
 r.position=m.position;r.fixture_id=i;r.up=m.up;r.fwd=m.fwd;r.scale=_Data3_Count>=6?Design[5].y:1;r.active=1;
 float2 target;bool spin=false;
 if(programmer()){PhProgram pr=Program[i];target=pr.aim.xy+float2(0,pr.meta.z);
  uint lane=phLaneIndex(pr.routing.z);
  if(lane>0){float4 l=Show[2+lane];float rank=phRank(m.rest,m.extra.z,pr.extra.x,pr.timing.z);
   if(phSpinFx(pr.timing.w)){target.x+=phSpinAngle(pr,l,rank);spin=true;}else target+=phMoveOffset(pr,l,lane,rank,i);}
  target.y=clamp(target.y,-135,135);if(!spin)target.x=clamp(target.x,-270,270);}
 else target=phAimAngles(m.up,m.fwd,referenceAim(m));
 float dt=clamp(_DeltaTime,0,.1);float2 cur=degrees(float2(r.pan,r.tilt));if(fresh)cur=target;
 float dp=spin?wrap180(target.x-cur.x):target.x-cur.x,dl=target.y-cur.y;float ease=min(1,dt*14);
 cur.x+=clamp(dp*ease,-pan_speed*dt,pan_speed*dt);cur.y+=clamp(dl*ease,-tilt_speed*dt,tilt_speed*dt);
 if(abs(cur.x)>540)cur.x-=360*sign(cur.x);
 r.pan=radians(cur.x);r.tilt=radians(cur.y);r.target_pan=radians(target.x);r.target_tilt=radians(target.y);Poses[i]=r;}
