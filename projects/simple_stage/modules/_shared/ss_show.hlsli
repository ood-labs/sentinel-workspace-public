// The show math shared by Lighting (movers, strobes, pixel runs): one program row per stable slot and layer, one Show
// State buffer from SS_Show. Forked from PHAGE's; the chase ranks are normalised by the stage (tools/ss_stage.py).
#ifndef SS_SHOW_HLSLI
#define SS_SHOW_HLSLI
#include "../_shared/ss_stage.hlsli"

// aim=(pan,tilt,level,ring) routing=(beam palette,ring palette,move lane,chase lane)
// movement=(color lane,pan size,tilt size,spread) timing=(width,offset,direction,look)
// meta=(commit,master,pitch,magic) extra=(order,-,-,-)
struct SsProgram{float4 aim;float4 routing;float4 movement;float4 timing;float4 meta;float4 extra;};

// Show State records (SS_Show):
// S[0]=(ref phase, enabled, pulse width, spread)  S[1]=(-, reverse, led peak, lane source 0 internal / 1 surface)
// S[2]=(programmer on, beat, bpm, magic)          S[3..7]=lanes 1-5 (phase, active, trigger, envelope)
// S[8..10]=palette A/B/C                          S[11]=(held strobe, strobe gate, blackout, build ramp)
// S[12]=(strobe rate /beat, strobe duty, -, running)
#define SS_SHOW_COUNT 13
#define SS_LANES 5
#define SS_LANE_BUILD 4
#define SS_LANE_PHRASE 5
uint ssLaneIndex(float v){return min((uint)max(v,0),(uint)SS_LANES);}

// Chase orders: 0 AROUND (round the stage from the front centre), 1 MIRROR (front to back on both sides), 2 OUT (from
// the centre line to the sides), 3 UP, 4 FRONT (front to back), 5 SIDE (across), 6 SHUFFLE, 7 GROUP (front truss,
// back truss, the floor strobes, the wall; group = SsMount.extra.z). Ranks come from the mount's rest position,
// normalised by the fixtures' extent (SS_RANK).
float ssRank(float4 rest,float group,float order,float reverse){
 uint o=(uint)round(order);float3 p=rest.xyz;float r;
 // atan2(0,0) is undefined on the GPU: a fixture on the centre axis ranks at 0 around.
 float around=abs(p.x)+abs(p.z)>1e-4?frac(atan2(p.x,p.z)/6.2831853+1.0):0;
 if(o==1)r=abs(around-.5)*2;
 else if(o==2)r=saturate(abs(p.x)/SS_RANK.x);
 else if(o==3)r=saturate((p.y-SS_RANK.z)/max(SS_RANK.w-SS_RANK.z,.1));
 else if(o==4)r=saturate((SS_RANK.y-p.z)/(2*SS_RANK.y));
 else if(o==5)r=saturate((p.x+SS_RANK.x)/(2*SS_RANK.x));
 else if(o==6)r=rest.w;
 else if(o==7)r=group>=0?(group+.5)/6.0:around;
 else r=around;
 return reverse>.5?1-r:r;
}
float ssPulse(float phase,float rank,float width,float spread){float age=frac(phase-saturate(rank)*spread);return smoothstep(0,.025,age)*(1-smoothstep(.08,max(.09,width),age));}
float ssHash(float3 p){return frac(sin(dot(p,float3(12.9898,78.233,37.719)))*43758.5453);}

// Movement FX code rides the LOOK value on movers:
// 16-47: 16 + repeats bits (x1/x2/x4/x8) + 4 RND gate + 8 JUMP + 16 STEP.
// 48-51: SPIN, one full turn per lane cycle x 1/4, 1/2, 1, 2 (continuous pan rotation).
uint ssMoverFx(float code){return code>=15.5&&code<47.5?(uint)(code-16):0;}
bool ssSpinFx(float code){return code>=47.5&&code<51.5;}
float ssSpinRate(float code){return exp2(round(code)-50);}
float2 ssStepPoint(float trigger,float offset,float reverse){
 const float2 Q[5]={float2(0,0),float2(1,.35),float2(-1,.35),float2(.55,-1),float2(-.55,-1)};
 int n=(int)fmod(trigger,1000)+(int)round(offset*5);if(reverse>.5)n=-n;return Q[((n%5)+5)%5];}
// 52-63: GLIDE, eased moves between positions: 52 + repeats bits (a new position every lane cycle x1/x2/x4/x8),
// +4 a random position per head instead of the five-point figure, +8 one random position per group (a formation the
// group moves to together). Each head sets off rank x spread + offset of a step late and takes width of a step to
// arrive, so a move ripples through a group and groups set off one after another.
bool ssGlideFx(float code){return code>=51.5&&code<63.5;}
float2 ssGlidePoint(float n,uint fx,float seed,float reverse){
 if((fx&12u)!=0u){float sd=fmod(n,997);return float2(ssHash(float3(seed,sd,1)),ssHash(float3(seed,sd,2)))*2-1;}
 const float2 Q[5]={float2(0,0),float2(1,.35),float2(-1,.35),float2(.55,-1),float2(-.55,-1)};
 int k=(int)fmod(fmod(n,5)+5,5);if(reverse>.5)k=(5-k)%5;return Q[k];}
float2 ssGlide(SsProgram pr,float4 l,uint lane,float rank,float slot,float group){
 uint fx=(uint)round(pr.timing.w)-52u;float rep=exp2((float)(fx&3u));
 float u=(l.z+l.x)*rep-saturate(rank)*pr.movement.w-pr.timing.y;
 float n=floor(u),e=smoothstep(0,1,saturate(frac(u)/max(.05,pr.timing.x)));
 float seed=(fx&8u)!=0u?group+101.0:slot;
 float2 p=lerp(ssGlidePoint(n-1,fx,seed,pr.timing.z),ssGlidePoint(n,fx,seed,pr.timing.z),e);
 return float2(pr.movement.y,pr.movement.z)*p*(lane==SS_LANE_BUILD?l.w:1);}
// Pan/tilt offset (degrees) for a movement lane. BUILD sweeps pan with a growing amplitude and
// raises tilt with the ramp; other lanes circle (a sweep or a nod with one size at 0), STEP, JUMP or GLIDE.
// group: the head's family, the seed of a GLIDE formation.
float2 ssMoveOffset(SsProgram pr,float4 l,uint lane,float rank,float slot,float group){
 if(ssGlideFx(pr.timing.w))return ssGlide(pr,l,lane,rank,slot,group);
 float2 amp=float2(pr.movement.y,pr.movement.z);uint fx=ssMoverFx(pr.timing.w);
 float ph=l.x-rank*pr.movement.w+pr.timing.y;
 if(fx&16)return amp*ssStepPoint(l.z,pr.timing.y,pr.timing.z)*(lane==SS_LANE_BUILD?l.w:1);
 if(fx&8){float sd=fmod(l.z,997);return amp*(float2(ssHash(float3(slot,sd,1)),ssHash(float3(slot,sd,2)))*2-1)*(lane==SS_LANE_BUILD?l.w:1);}
 if(lane==SS_LANE_BUILD)return float2(amp.x*sin(ph*6.2831853),amp.y)*l.w;   // the ramp, from 0 (state.hlsl)
 return l.y*float2(amp.x*sin(ph*6.2831853),amp.y*cos(ph*6.2831853));
}
float2 ssMoveOffset(SsProgram pr,float4 l,uint lane,float rank,float slot){return ssMoveOffset(pr,l,lane,rank,slot,slot);}
// Continuous spin angle (degrees, 0-360) for SPIN codes; lanes must be REPEAT-style for smooth turns.
float ssSpinAngle(SsProgram pr,float4 l,float rank){
 float cyc=fmod(l.z,64.0)+l.x-rank*pr.movement.w+pr.timing.y;
 return 360.0*frac(cyc*ssSpinRate(pr.timing.w)*(pr.timing.z>.5?-1:1));
}
// Intensity chase: lane pulse with repeats and RND gate (movers), shared by strobe/bar CHASE.
// HOLD (codes 24-27, the JMP bit, which moves heads but never touched light): a window instead of a pulse, open for
// WIDTH of each lane cycle (x repeats) from OFFSET, rippling through the group by rank x SPREAD, closed otherwise; at
// its narrowest WIDTH it never opens. Windows on different groups hand the light from one group to the next.
float ssChase(SsProgram pr,float4 l,float rank,float slot){
 uint fx=ssMoverFx(pr.timing.w);float p=(l.x+pr.timing.y)*exp2((float)(fx&3));
 if((fx&8u)!=0u){float age=frac(p-saturate(rank)*pr.movement.w);float w=max(.01,pr.timing.x);
  return l.y*smoothstep(0,.012,age)*(1-smoothstep(w-.012,w,age))*saturate((w-.01)*200);}
 float v=l.y*ssPulse(p,rank,pr.timing.x,pr.movement.w);
 if(fx&4){float n=floor(p-saturate(rank)*pr.movement.w);v*=ssHash(float3(slot,fmod(l.z,997),n))<.34?1:0;}
 return v;
}
#endif
