// BLINK_Previs / tiles.hlsl: laser_lab LS_Air tiles.hlsl (1563058e). Per 16x16 screen tile, a
// 1024-bit mask of the scan records whose swept triangle can touch it. Only change: rays come
// from the site camera (mirrored z) so the frusta match the render pass.
#include "site.hlsli"
struct ScreenRec {float4 ab;float4 cd;float4 bounds;float4 meta;};
StructuredBuffer<ScreenRec> Screens:register(t0);
RWStructuredBuffer<uint> OutputBuffer:register(u0);
float3 cornerRay(float2 pixel){
 float2 uv=pixel/_Resolution,ndc=float2(uv.x*2-1,1-uv.y*2);
 float4 farW=mul(_InvViewProjMatrix,float4(ndc,1,1));farW/=farW.w;
 return normalize(farW.xyz-_CameraPos)*float3(1,1,-1);
}
float3 inwardNormal(float3 a,float3 b,float3 middle){float3 n=normalize(cross(a,b));return dot(n,middle)<0?-n:n;}
bool planeOverlap(float3 normal,float3 a,float3 b,float3 c,float radius){
 return max(dot(normal,a),max(dot(normal,b),dot(normal,c)))>=-radius;
}
[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){
 uint2 tiles=((uint2)_Resolution+15)/16;
 if(any(id.xy>=tiles)||any(id.xy>=256))return;
 uint tile=id.y*tiles.x+id.x,base=tile*129,count=0;
 uint masks[128];[loop]for(uint word=0;word<128;word++)masks[word]=0;
 float2 lo=id.xy*16-5,hi=id.xy*16+21;
 float3 tl=cornerRay(lo),tr=cornerRay(float2(hi.x,lo.y)),br=cornerRay(hi),bl=cornerRay(float2(lo.x,hi.y));
 float3 center=normalize(tl+tr+br+bl);
 float3 leftN=inwardNormal(bl,tl,center),rightN=inwardNormal(tr,br,center);
 float3 topN=inwardNormal(tl,tr,center),bottomN=inwardNormal(br,bl,center);
 float3 eye=camPos();
 uint records=min((uint)Screens[0].meta.x,4095u);
 for(uint i=1;i<=records;i++){
  ScreenRec s=Screens[i];if(s.meta.x==0)continue;
  float3 a=s.ab.xyz-eye,b=s.cd.xyz-eye,c=s.bounds.xyz-eye;float radius=s.ab.w;
  bool hit=planeOverlap(leftN,a,b,c,radius)&&planeOverlap(rightN,a,b,c,radius)&&planeOverlap(topN,a,b,c,radius)&&planeOverlap(bottomN,a,b,c,radius)&&planeOverlap(center,a,b,c,radius);
  if(hit){masks[i>>5]|=1u<<(i&31);count++;}
 }
 OutputBuffer[base]=count;
 [loop]for(uint outputWord=0;outputWord<128;outputWord++)OutputBuffer[base+1+outputWord]=masks[outputWord];
}
