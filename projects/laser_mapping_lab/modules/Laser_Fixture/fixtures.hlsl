#include "pose.hlsli"
struct Fixture {float4 aperture;float4 right;float4 up;float4 forward;float4 emission;};
RWStructuredBuffer<Fixture> OutputBuffer:register(u0);
[numthreads(1,1,1)]
void main(uint3 tid:SV_DispatchThreadID){
 float3 emission=0;
 if(_Data0_Count>0){
  float cycle=max(_Data0[0].endpoints.y,1e-7);
  for(uint s=1;s<=min((uint)_Data0[0].endpoints.x,_Data0_Count-1);s++){
   if(_Data0[s].timing.w<.5)emission+=.5*(_Data0[s].color0.rgb*_Data0[s].color0.a+_Data0[s].color1.rgb*_Data0[s].color1.a)*_Data0[s].timing.y/cycle;
  }
 }
 Fixture header=(Fixture)0;header.aperture.w=clamp(projector_count,1,4);OutputBuffer[0]=header;
 for(uint i=0;i<4;i++){
  Fixture f=(Fixture)0;
  if(i<(uint)clamp(projector_count,1,4)){
   f.aperture=float4(apertureFor(i),power);
   f.right=float4(orientFixture(float3(1,0,0),i),i+1);
   f.up=float4(orientFixture(float3(0,1,0),i),radians(yoke_angle));
   f.forward=float4(orientFixture(float3(0,0,1),i),1);
   f.emission=float4(emission*power*fixtureGate(i),1);
  }
  OutputBuffer[i+1]=f;
 }
}
