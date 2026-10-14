// Mover motors. Programmer: pan/tilt from the program row (+ pitch) plus the lane's movement FX
// (circle, BUILD sweep, STEP, JUMP, a GLIDE lean) or a continuous SPIN. Reference (no programmer): every family
// aims a designed default so the rig reads without a Surface. Eased toward target, speed-limited, and held inside
// the pan and tilt the fixture's GDTF allows (Rig Slots, rig_slots.hlsl).
#include "lighting.hlsli"
#include "../_shared/ss_rig.hlsli"
StructuredBuffer<SsMount> Mounts:register(t0);
StructuredBuffer<float4> Show:register(t1);
StructuredBuffer<SsProgram> Program:register(t2);
StructuredBuffer<SsRigSlot> RigSlots:register(t3);
RWStructuredBuffer<SsMoverPose> Poses:register(u0);
bool programmer(){return _Data2_Count>=SS_SLOTS&&_Data1_Count>=SS_SHOW_COUNT&&Show[2].x>.5;}
// Reference aims: the front row fans down onto the crowd, the back row throws a flatter, wider fan out over it from
// higher up, and a guest head looks straight down from wherever it hangs.
float3 referenceAim(SsMount m){uint f=(uint)round(m.extra.x);float x=m.position.x;
 if(f==0)return normalize(float3(x*.16,-.5,1));
 if(f==1)return normalize(float3(x*.22,-.14,1));
 return float3(0,-1,0);}
float wrap180(float a){return a-360*floor((a+180)/360);}
// GLIDE leans the beam: its pan size tips it toward world X (across the stage) and its tilt size raises it in the
// head's own frame. Every head of a group leans the same way, so a formation moves as one body instead of twisting
// round its ring as equal pan offsets in each head's turned frame do. With ORDER MIRROR the stage's two halves lean
// opposite ways, so the group fans open and closed about the centre line (heads on it only rise). The lean is split
// between the head's tilt and pan directions (damped least squares): near its own pan axis a beam would need up to
// half a turn of pan to lean a few degrees, so pan there is damped (at most 1.25 x the lean) and the yoke never
// whirls; the split is linear, so a lean eases as the GLIDE does.
float2 leanAim(SsMount m,float2 aim,float2 g){
 float2 a=float2(aim.x,aim.y+g.y);float p=radians(a.x),t=radians(a.y),c=cos(t);float3 x=cross(m.up,m.fwd);
 float3 ep=-x*cos(p)+m.fwd*sin(p);
 float3 et=x*(sin(p)*sin(t))+m.up*c+m.fwd*(cos(p)*sin(t));
 float l=clamp(g.x,-60,60);
 return a+float2(ep.x*l*c/(c*c+.16),et.x*l);}
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=SS_MOVERS)return;
 SsMount m=Mounts[i];SsMoverPose r=Poses[i];
 if(i>=_Data0_Count||m.active<.5||m.kind!=0){Poses[i]=(SsMoverPose)0;return;}
 bool fresh=r.active<.5;
 r.position=m.position;r.fixture_id=i;r.up=m.up;r.fwd=m.fwd;r.scale=SS_MOVER_SCALE;r.active=1;
 float2 target;bool spin=false;
 if(programmer()){SsProgram pr=Program[i];target=pr.aim.xy+float2(0,pr.meta.z);
  uint lane=ssLaneIndex(pr.routing.z);
  if(lane>0){float4 l=Show[2+lane];float rank=ssRank(m.rest,m.extra.z,pr.extra.x,pr.timing.z);
   if(ssSpinFx(pr.timing.w)){target.x+=ssSpinAngle(pr,l,rank);spin=true;}else if(ssGlideFx(pr.timing.w)){float2 g=ssGlide(pr,l,lane,rank,i,m.extra.x);
    if(round(pr.extra.x)==1)g.x*=clamp(m.position.x/.5,-1,1);
    target=leanAim(m,target,g);}
   else target+=ssMoveOffset(pr,l,lane,rank,i,m.extra.x);}
  if(!spin)target.x=clamp(target.x,RigSlots[i].limits.x,RigSlots[i].limits.y);}
 else target=ssAimAngles(m.up,m.fwd,referenceAim(m));
 target.y=clamp(target.y,RigSlots[i].limits.z,RigSlots[i].limits.w);
 float dt=clamp(_DeltaTime,0,.1);float2 cur=degrees(float2(r.pan,r.tilt));if(fresh)cur=target;
 float dp=spin?wrap180(target.x-cur.x):target.x-cur.x,dl=target.y-cur.y;float ease=min(1,dt*14);
 cur.x+=clamp(dp*ease,-pan_speed*dt,pan_speed*dt);cur.y+=clamp(dl*ease,-tilt_speed*dt,tilt_speed*dt);
 if(abs(cur.x)>540)cur.x-=360*sign(cur.x);
 r.pan=radians(cur.x);r.tilt=radians(cur.y);r.target_pan=radians(target.x);r.target_tilt=radians(target.y);Poses[i]=r;}
