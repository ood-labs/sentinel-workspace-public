// One working mapping, always bank 0 of the points buffer (the buffer keeps its three-bank size
// so saved projects and presets stay valid; see update.hlsl for the one-time migration).
#ifndef BANK
#define BANK 0
#endif
#include "quad.hlsli"
struct Scan {float4 endpoints,color0,color1,timing,meta;};
StructuredBuffer<float4> Points:register(t1);
float2 controlPoint(int i){return Points[BANK+i].xy;}
float3x3 transform(){return quadMatrix((controlPoint(0)-.1)/.8,(controlPoint(4)-.1)/.8,(controlPoint(24)-.1)/.8,(controlPoint(20)-.1)/.8);}
float2 residual(int x,int y,float3x3 m){int2 k=clamp(int2(x,y),0,4);return (controlPoint(k.y*5+k.x)-.1)/.8-applyQuad(m,float2(k)/4);}
float2 mappedUV(float2 uv){
 float3x3 m=transform();float2 z=saturate(uv)*4;int2 k=min((int2)floor(z),3);float2 t=z-k;
 float4 wx=weights(t.x),wy=weights(t.y);float2 d=0;
 [unroll]for(int j=0;j<4;j++)[unroll]for(int i=0;i<4;i++)d+=residual(k.x+i-1,k.y+j-1,m)*wx[i]*wy[j];
 return applyQuad(m,uv)+d;
}
// Scanner correction, modelled in the laser's own field (centred on its optical axis, in slot-extent
// units), so an off-centre mapping gets more correction on the side further from the axis.
//   spacing: atan/tan per axis. Evens out line spacing that drifts progressively across the field.
//   bow:     x pulled by y^2, y by x^2. Positive bows lines outward, cancelling a pincushion bow.
// Corner-anchored: the correction's value at the four mapped corners is removed bilinearly, so the
// corners stay exactly where the handles put them and only the lines between them move.
// tan's argument is clamped under pi/2 so a strong negative Spacing can't reach the pole at the field edge.
float spacingAxis(float v,float s){return abs(s)<1e-4?v:(s>0?atan(v*s)/s:tan(clamp(v*-s,-1.45,1.45))/-s);}
// c = the laser's straight-on point in the field, the centre the distortion is measured from.
float2 scannerShape(float2 q,float4 k,float2 c){q-=c;q=float2(spacingAxis(q.x,k.z),spacingAxis(q.y,k.w));return float2(q.x*(1-k.x*q.y*q.y),q.y*(1-k.y*q.x*q.x))+c;}
float slotExtent(){return extent_a;}
// The lattice exactly as the laser will draw it, in editor uv (0..1).
float2 correctedUV(float2 uv){float4 k=float4(pincushion_x,pincushion_y,spacing_x,spacing_y);float2 ctr=float2(centre_x,-centre_y);float e=slotExtent();
 float2 q=(mappedUV(uv)*2-1)*e;
 float2 d00=(mappedUV(float2(0,0))*2-1)*e,d10=(mappedUV(float2(1,0))*2-1)*e,d01=(mappedUV(float2(0,1))*2-1)*e,d11=(mappedUV(float2(1,1))*2-1)*e;
 d00=scannerShape(d00,k,ctr)-d00;d10=scannerShape(d10,k,ctr)-d10;d01=scannerShape(d01,k,ctr)-d01;d11=scannerShape(d11,k,ctr)-d11;
 q=scannerShape(q,k,ctr)-lerp(lerp(d00,d10,uv.x),lerp(d01,d11,uv.x),uv.y);return (q/e+1)*.5;}
float2 warp(float2 p){return (mappedUV((p/extent_a+1)*.5)*2-1)*extent_a;}
bool validMapping(){
 if(!convex(controlPoint(0),controlPoint(4),controlPoint(24),controlPoint(20)))return false;
 [loop]for(int y=0;y<=8;y++)[loop]for(int x=0;x<=8;x++){
  float2 uv=float2(x,y)/8,q=mappedUV(uv);
  float2 dx=mappedUV(uv+float2(.001,0))-q,dy=mappedUV(uv+float2(0,.001))-q;
  if(!all(isfinite(q))||cross2(dx,dy)<1e-9)return false;
 }
 return true;
}
