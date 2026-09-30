// PHAGE show math shared by Lighting (movers, strobes), LED (bars) and Kinetics (truss axes).
// One program row per stable slot; one Show State buffer from Phage_Show.
#ifndef PHAGE_SHOW_HLSLI
#define PHAGE_SHOW_HLSLI

// aim=(pan,tilt,level,ring) routing=(beam palette,ring palette,move lane,chase lane)
// movement=(color lane,pan size,tilt size,spread) timing=(width,offset,direction,look)
// meta=(commit,master,pitch,magic) extra=(order,-,-,-)
struct PhProgram{float4 aim;float4 routing;float4 movement;float4 timing;float4 meta;float4 extra;};

// Show State records (Phage_Show):
// S[0]=(ref phase, enabled, pulse width, spread)  S[1]=(-, reverse, led peak, lane source 0 internal / 1 surface)
// S[2]=(programmer on, beat, bpm, magic)          S[3..7]=lanes 1-5 (phase, active, trigger, envelope)
// S[8..10]=palette A/B/C                          S[11]=(held strobe, strobe gate, blackout, build ramp)
// S[12]=(strobe rate /beat, strobe duty, kinetics on, -)
#define PH_SHOW_COUNT 13
#define PH_LANES 5
#define PH_LANE_BUILD 4
#define PH_LANE_PHRASE 5
uint phLaneIndex(float v){return min((uint)max(v,0),(uint)PH_LANES);}

// Chase orders: 0 AROUND, 1 MIRROR (front to back on both sides), 2 OUT, 3 UP, 4 FRONT, 5 SIDE,
// 6 SHUFFLE, 7 LEG (by leg, then around). Ranks come from the REST position so a chase stays
// attached to its fixtures while the truss moves.
float phRank(float4 rest,float leg,float order,float reverse){
 uint o=(uint)round(order);float3 p=rest.xyz;float r;
 // atan2(0,0) is undefined on the GPU: fixtures on the body axis rank at 0 around.
 float around=abs(p.x)+abs(p.z)>1e-4?frac(atan2(p.x,p.z)/6.2831853+1.0):0;
 if(o==1)r=abs(around-.5)*2;
 else if(o==2)r=saturate(length(p.xz)/19.0);
 else if(o==3)r=saturate(p.y/22.0);
 else if(o==4)r=saturate((16.0-p.z)/32.0);
 else if(o==5)r=saturate((p.x+19.0)/38.0);
 else if(o==6)r=rest.w;
 else if(o==7)r=leg>=0?(leg+.5)/6.0:around;
 else r=around;
 return reverse>.5?1-r:r;
}
float phPulse(float phase,float rank,float width,float spread){float age=frac(phase-saturate(rank)*spread);return smoothstep(0,.025,age)*(1-smoothstep(.08,max(.09,width),age));}
float phHash(float3 p){return frac(sin(dot(p,float3(12.9898,78.233,37.719)))*43758.5453);}

// Movement FX code rides the LOOK value on movers and axes:
// 16-47: 16 + repeats bits (x1/x2/x4/x8) + 4 RND gate + 8 JUMP + 16 STEP.
// 48-51: SPIN, one full turn per lane cycle x 1/4, 1/2, 1, 2 (continuous pan rotation).
uint phMoverFx(float code){return code>=15.5&&code<47.5?(uint)(code-16):0;}
bool phSpinFx(float code){return code>=47.5&&code<51.5;}
float phSpinRate(float code){return exp2(round(code)-50);}
float2 phStepPoint(float trigger,float offset,float reverse){
 const float2 Q[5]={float2(0,0),float2(1,.35),float2(-1,.35),float2(.55,-1),float2(-.55,-1)};
 int n=(int)fmod(trigger,1000)+(int)round(offset*5);if(reverse>.5)n=-n;return Q[((n%5)+5)%5];}
// Pan/tilt offset (degrees) for a movement lane. BUILD sweeps pan with a growing amplitude and
// raises tilt with the ramp; other lanes circle, STEP or JUMP.
float2 phMoveOffset(PhProgram pr,float4 l,uint lane,float rank,float slot){
 float2 amp=float2(pr.movement.y,pr.movement.z);uint fx=phMoverFx(pr.timing.w);
 float ph=l.x-rank*pr.movement.w+pr.timing.y;
 if(fx&16)return amp*phStepPoint(l.z,pr.timing.y,pr.timing.z)*(lane==PH_LANE_BUILD?l.y:1);
 if(fx&8){float sd=fmod(l.z,997);return amp*(float2(phHash(float3(slot,sd,1)),phHash(float3(slot,sd,2)))*2-1)*(lane==PH_LANE_BUILD?l.y:1);}
 if(lane==PH_LANE_BUILD)return float2(amp.x*sin(ph*6.2831853),amp.y)*l.y;
 return l.y*float2(amp.x*sin(ph*6.2831853),amp.y*cos(ph*6.2831853));
}
// Continuous spin angle (degrees, 0-360) for SPIN codes; lanes must be REPEAT-style for smooth turns.
float phSpinAngle(PhProgram pr,float4 l,float rank){
 float cyc=fmod(l.z,64.0)+l.x-rank*pr.movement.w+pr.timing.y;
 return 360.0*frac(cyc*phSpinRate(pr.timing.w)*(pr.timing.z>.5?-1:1));
}
// Intensity chase: lane pulse with repeats and RND gate (movers), shared by strobe/bar CHASE.
float phChase(PhProgram pr,float4 l,float rank,float slot){
 uint fx=phMoverFx(pr.timing.w);float p=(l.x+pr.timing.y)*exp2((float)(fx&3));
 float v=l.y*phPulse(p,rank,pr.timing.x,pr.movement.w);
 if(fx&4){float n=floor(p-saturate(rank)*pr.movement.w);v*=phHash(float3(slot,fmod(l.z,997),n))<.34?1:0;}
 return v;
}
#endif
