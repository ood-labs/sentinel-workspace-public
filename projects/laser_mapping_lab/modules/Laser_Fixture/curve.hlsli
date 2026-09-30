#include "stream.hlsli"
float2 curvePoint(uint j,uint count,float t){
 float2 p0=Stream[j].endpoints.xy,p1=Stream[j].endpoints.zw;
 float2 chord=p1-p0,m0=chord,m1=chord;
 if(Stream[j].timing.w>.5||dot(chord,chord)<1e-14)return lerp(p0,p1,t);
 // Only reconstruct contiguous illuminated segments within the same shape.
 // Blanking and stationary dwell records are hard boundaries.
 if(j>1){
  float2 prev=Stream[j-1].endpoints.zw-Stream[j-1].endpoints.xy;
  float2 gap=Stream[j-1].endpoints.zw-p0;
  if(Stream[j-1].timing.w<.5&&dot(gap,gap)<1e-12&&dot(prev,prev)>1e-14)
   m0=.5*(prev+chord);
 }
 if(j<count){
  float2 next=Stream[j+1].endpoints.zw-Stream[j+1].endpoints.xy;
  float2 gap=Stream[j+1].endpoints.xy-p1;
  if(Stream[j+1].timing.w<.5&&dot(gap,gap)<1e-12&&dot(next,next)>1e-14)
   m1=.5*(chord+next);
 }
 float t2=t*t,t3=t2*t;
 float2 curved=(2*t3-3*t2+1)*p0+(t3-2*t2+t)*m0+(-2*t3+3*t2)*p1+(t3-t2)*m1;
 return lerp(lerp(p0,p1,t),curved,curve_smoothing);
}
