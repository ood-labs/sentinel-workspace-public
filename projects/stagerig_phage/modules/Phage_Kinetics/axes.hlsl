// Motion control for the eight truss axes: programmer targets (+ lane FX) -> trapezoidal moves.
StructuredBuffer<float4> DesignIn:register(t0);
StructuredBuffer<float4> Show:register(t1);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
#include "../_shared/phage_show.hlsli"
StructuredBuffer<PhProgram> Program:register(t2);
RWStructuredBuffer<float4> A:register(u0);
#include "kin_common.hlsli"

// Program pan/tilt (degrees) -> physical axis values.
float2 mapAxis(uint k,float2 pt){
 if(k==0)return float2(clamp(pt.y/90*2.4,-2.4,2.0),clamp(pt.x,-30,30));
 if(k==1)return float2(pt.x,clamp(pt.y/90*2.4,-1.2,2.4));
 return float2(clamp(pt.x/90*2.5,-2.5,2.5),clamp(pt.y/90*4.0,0,4.5));
}
float2 limits(uint k,uint c){ // (max speed, max accel) per component, before the speed multiplier
 if(k==0)return c==0?float2(1.0,1.6):float2(14,22);
 if(k==1)return c==0?float2(120,170):float2(1.4,3.0);
 return c==0?float2(2.6,10):float2(3.8,16);
}
float2 move(float x,float v,float target,float2 lim,float dt){
 float e=target-x;float vd=sign(e)*min(lim.x,sqrt(2*lim.y*abs(e)*.85));
 v+=clamp(vd-v,-lim.y*dt,lim.y*dt);float n=x+v*dt;
 if((target-n)*e<0||abs(e)<1e-4){n=target;v=0;}
 return float2(n,v);
}
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 if(A[24].x!=AX_MAGIC){for(uint j=0;j<AX_RECORDS;j++)A[j]=0;A[24].x=AX_MAGIC;}
 float dt=clamp(_DeltaTime,0,.1);float t=A[24].z+dt;A[24].z=fmod(t,3600);
 bool designOk=_Data0_Count>=17&&DesignIn[16].w==260929;if(!designOk)return;
 PhDesign D=phLoad();
 bool prog=_Data2_Count>=PH_SLOTS&&_Data1_Count>=PH_SHOW_COUNT&&Show[2].x>.5&&Show[12].z>.5;
 uint mode=(uint)drive;if(mode==0&&!prog)mode=3;A[24].y=mode;
 for(uint k=0;k<PH_AXES;k++){
  float2 raw=0;
  if(mode==0){PhProgram pr=Program[PH_AXIS0+k];float2 pt=pr.aim.xy;uint lane=phLaneIndex(pr.routing.z);
   if(lane>0){float4 l=Show[2+lane];PhMount rm=phAxisMount(D,phRest(),k);
    float rank=phRank(float4(rm.position,phHash1((PH_AXIS0+k)*1.618+.37)),rm.extra.z,pr.extra.x,pr.timing.z);
    if(phSpinFx(pr.timing.w))pt.x+=phSpinAngle(pr,l,rank);else pt+=phMoveOffset(pr,l,lane,rank,PH_AXIS0+k);}
   raw=mapAxis(k,pt);}
  else if(mode==1){
   if(k==0)raw=float2(manual_height,manual_yaw);else if(k==1)raw=float2(manual_spin,manual_contract);
   else raw=(manual_leg<0||manual_leg==(int)k-2)?float2(manual_swing,manual_lift):float2(0,0);}
  else if(mode==2){
   if(k==0)raw=float2(.9*sin(t*.35),8*sin(t*.13));
   else if(k==1)raw=float2(fmod(t*24,360),.9+.9*sin(t*.27));
   else{float ph=t*1.2-(float)(k-2)*1.047;raw=float2(.8*cos(ph),max(0,1.8*sin(ph)));}}
  // component a may be a spin (capsid): unwrap so a continuous turn never reverses.
  float4 s0=A[3*k],s1=A[3*k+1];
  // Non-finite state (exponent all ones) restarts the axis at rest instead of staying poisoned.
  if(any((asuint(float4(raw,s0.xy))&0x7f800000u)==0x7f800000u)||any((asuint(s1)&0x7f800000u)==0x7f800000u)){raw=0;s0=0;s1=0;}
  float ta=raw.x;
  if(k==1){float d=raw.x-s1.z;d-=360*round(d/360);s1.w+=d;s1.z=raw.x;
   if(s1.w-s0.x>540)s1.w-=360;if(s0.x-s1.w>540)s1.w+=360;ta=s1.w;}
  float sp=max(.05,speed);float2 la=limits(k,0)*float2(sp,sp*sp),lb=limits(k,1)*float2(sp,sp*sp);
  float2 ma=move(s0.x,s0.z,ta,la,dt),mb=move(s0.y,s0.w,raw.y,lb,dt);
  s0=float4(ma.x,mb.x,ma.y,mb.y);
  if(k==1&&abs(s0.x)>360){float w=360*sign(s0.x);s0.x-=w;s1.w-=w;}
  s1.xy=float2(ta,raw.y);A[3*k]=s0;A[3*k+1]=s1;A[3*k+2]=float4(raw,0,0);
 }
}
