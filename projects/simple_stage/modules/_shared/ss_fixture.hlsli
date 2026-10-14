// Fixture kinematics shared by SS_Lighting (aims, optics) and SS_Renderer (geometry), so the
// beam that is lit and the head that is drawn can never disagree. Mover model units are metres at
// scale 1; the mount frame is (cross(up,fwd), up, fwd) of the SsMount (_shared/ss_slots.hlsli).
#ifndef SS_FIXTURE_HLSLI
#define SS_FIXTURE_HLSLI
// Lighting's Optics buffer: SS_MOVERS movers x SS_OPT_PER records (beam, then 24 ring pixels), then SS_STROBES strobe
// records in the SsStrobe layout (same 80-byte stride), so the renderer spends one data input on both
// (_shared/ss_layout.hlsli).
#include "../_shared/ss_layout.hlsli"
struct SsMoverPose{float3 position;float fixture_id;float3 up;float pan;float3 fwd;float tilt;float target_pan;float target_tilt;float scale;float active;};
// Movers: padding.x is 1 on a halo cell, padding.y the desk level (0-1) the DMX output carries.
struct SsOptical{float3 position;float fixture_id;float3 normal;float local_id;float3 colour;float intensity;float beam_tangent;float field_tangent;float reach;float active;float frost;float3 padding;};
// Strobe: tube along `up`, emitting along `fwd`; levels already include master, chase and flash.
struct SsStrobe{float3 position;float fixture_id;float3 fwd;float tube;float3 up;float plate;float3 tube_colour;float length;float3 plate_colour;float active;};
// A strobe record read through a SsOptical view of the Optics buffer (row for row, same stride).
SsStrobe ssStrobeOf(SsOptical o){SsStrobe s;s.position=o.position;s.fixture_id=o.fixture_id;s.fwd=o.normal;s.tube=o.local_id;
 s.up=o.colour;s.plate=o.intensity;s.tube_colour=float3(o.beam_tangent,o.field_tangent,o.reach);s.length=o.active;
 s.plate_colour=float3(o.frost,o.padding.x,o.padding.y);s.active=o.padding.z;return s;}
float3 ssRx(float3 p,float a){float s=sin(a),c=cos(a);return float3(p.x,c*p.y-s*p.z,s*p.y+c*p.z);}
float3 ssRy(float3 p,float a){float s=sin(a),c=cos(a);return float3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);}
float3 ssMountVec(float3 up,float3 fwd,float3 v){return cross(up,fwd)*v.x+up*v.y+fwd*v.z;}
float3 ssBasePoint(SsMoverPose r,float3 p){return r.position+ssMountVec(r.up,r.fwd,p*r.scale);}
float3 ssYokePoint(SsMoverPose r,float3 p){return r.position+ssMountVec(r.up,r.fwd,(float3(0,.075,0)+ssRy(p,r.pan))*r.scale);}
float3 ssYokeNormal(SsMoverPose r,float3 n){return ssMountVec(r.up,r.fwd,ssRy(n,r.pan));}
float3 ssHeadPoint(SsMoverPose r,float3 p){return r.position+ssMountVec(r.up,r.fwd,(float3(0,.075,0)+ssRy(float3(0,.152,0)+ssRx(p,r.tilt),r.pan))*r.scale);}
float3 ssHeadNormal(SsMoverPose r,float3 n){return ssMountVec(r.up,r.fwd,ssRy(ssRx(n,r.tilt),r.pan));}
// The Halo Beam GDTF (tools/ss_gdtf.py) in PHAGE's terms. Its frame is (side, fwd, -up) of the mount, so GDTF pan
// is PHAGE's pan negated and GDTF tilt is PHAGE's tilt less 90 (GDTF tilt 0 points the beam along the hanging axis,
// PHAGE's at right angles to it). The real head tilts +-135 about the hanging axis, which is PHAGE tilt -45 to 135:
// a beam cannot aim back into its own base, so the motors clamp to it and the drawn beam is one the fixture can make.
#define SS_TILT_MIN -45.0
#define SS_TILT_MAX 135.0
float ssGdtfPan(float panRad){float g=-degrees(panRad);return abs(g)>270?g-360*sign(g):g;}
float ssGdtfTilt(float tiltRad){return clamp(degrees(tiltRad)-90,-135,135);}
// World beam direction -> motor angles (degrees) for a mount frame; inverse of ssHeadNormal(0,0,-1).
float2 ssAimAngles(float3 up,float3 fwd,float3 dir){float3 x=cross(up,fwd);float3 q=float3(dot(dir,x),dot(dir,up),dot(dir,fwd));
 return degrees(float2(abs(q.x)+abs(q.z)>1e-6?atan2(-q.x,-q.z):0,asin(clamp(q.y,-1,1))));}
#endif
