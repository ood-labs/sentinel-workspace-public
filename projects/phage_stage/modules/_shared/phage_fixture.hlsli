// Fixture kinematics shared by Phage_Lighting (aims, optics) and Phage_Renderer (geometry), so the
// beam that is lit and the head that is drawn can never disagree. Mover model units are metres at
// scale 1; the mount frame is (cross(up,fwd), up, fwd) from phage_anatomy's PhMount.
#ifndef PHAGE_FIXTURE_HLSLI
#define PHAGE_FIXTURE_HLSLI
// Lighting's Optics buffer: 128 movers x 25 records (beam, then 24 ring pixels), then 48 strobe
// records in the PhStrobe layout (same 80-byte stride), so the renderer spends one data input on both.
#define PH_OPT_PER 25
#define PH_OPT_STROBE0 3200
#define PH_OPT_COUNT 3248
struct PhMoverPose{float3 position;float fixture_id;float3 up;float pan;float3 fwd;float tilt;float target_pan;float target_tilt;float scale;float active;};
struct PhOptical{float3 position;float fixture_id;float3 normal;float local_id;float3 colour;float intensity;float beam_tangent;float field_tangent;float reach;float active;float frost;float3 padding;};
// Strobe: tube along `up`, emitting along `fwd`; levels already include master, chase and flash.
struct PhStrobe{float3 position;float fixture_id;float3 fwd;float tube;float3 up;float plate;float3 tube_colour;float length;float3 plate_colour;float active;};
// A strobe record read through a PhOptical view of the Optics buffer (row for row, same stride).
PhStrobe phStrobeOf(PhOptical o){PhStrobe s;s.position=o.position;s.fixture_id=o.fixture_id;s.fwd=o.normal;s.tube=o.local_id;
 s.up=o.colour;s.plate=o.intensity;s.tube_colour=float3(o.beam_tangent,o.field_tangent,o.reach);s.length=o.active;
 s.plate_colour=float3(o.frost,o.padding.x,o.padding.y);s.active=o.padding.z;return s;}
float3 phRx(float3 p,float a){float s=sin(a),c=cos(a);return float3(p.x,c*p.y-s*p.z,s*p.y+c*p.z);}
float3 phRy(float3 p,float a){float s=sin(a),c=cos(a);return float3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);}
float3 phMountVec(float3 up,float3 fwd,float3 v){return cross(up,fwd)*v.x+up*v.y+fwd*v.z;}
float3 phBasePoint(PhMoverPose r,float3 p){return r.position+phMountVec(r.up,r.fwd,p*r.scale);}
float3 phYokePoint(PhMoverPose r,float3 p){return r.position+phMountVec(r.up,r.fwd,(float3(0,.075,0)+phRy(p,r.pan))*r.scale);}
float3 phYokeNormal(PhMoverPose r,float3 n){return phMountVec(r.up,r.fwd,phRy(n,r.pan));}
float3 phHeadPoint(PhMoverPose r,float3 p){return r.position+phMountVec(r.up,r.fwd,(float3(0,.075,0)+phRy(float3(0,.152,0)+phRx(p,r.tilt),r.pan))*r.scale);}
float3 phHeadNormal(PhMoverPose r,float3 n){return phMountVec(r.up,r.fwd,phRy(phRx(n,r.tilt),r.pan));}
// World beam direction -> motor angles (degrees) for a mount frame; inverse of phHeadNormal(0,0,-1).
float2 phAimAngles(float3 up,float3 fwd,float3 dir){float3 x=cross(up,fwd);float3 q=float3(dot(dir,x),dot(dir,up),dot(dir,fwd));
 return degrees(float2(abs(q.x)+abs(q.z)>1e-6?atan2(-q.x,-q.z):0,asin(clamp(q.y,-1,1))));}
#endif
