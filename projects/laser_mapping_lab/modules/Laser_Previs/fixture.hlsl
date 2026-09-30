// Laser_Previs / fixture.hlsl: the laser's RAW 10 housing as linear colour + camera-ray depth
// (w = 1000 where nothing is hit). The render pass depth-tests beams and the scene against it.
#define FIX _Data1
#define FIX_COUNT _Data1_Count
#include "site.hlsli"
#include "raw10_parts.hlsli"
#include "raw10.hlsli"
RWTexture2D<float4> OutputUAV:register(u0);
#define FIX_FN fixtureA
#include "fixture_loop.hlsli"
[numthreads(8,8,1)]
void main(uint3 tid:SV_DispatchThreadID){
 uint w,h;OutputUAV.GetDimensions(w,h);if(tid.x>=w||tid.y>=h)return;
 float4 result=float4(0,0,0,1000);
 if(show_fixtures){
  float3 rd=camRayAt(tid.xy+.5),eye=camPos();
  result=fixtureA(eye,rd,result);
 }
 OutputUAV[tid.xy]=result;
}
