#include "stage_types.hlsli"
// Truss expansion shared by the tube pass and the preview (the preview draws the real tubes). A span or leg is four
// chords, zig-zag lacing on each face and an end frame at each end; a corner block is the twelve edges of its cube.
void trussFrame(SsMember m,out float3 D,out float3 U,out float3 V){
 D=normalize(m.b.xyz-m.a.xyz);float3 r=m.up.xyz-D*dot(m.up.xyz,D);
 if(dot(r,r)<1e-5)r=abs(D.y)<.9?float3(0,1,0):float3(1,0,0);
 V=normalize(r);U=normalize(cross(V,D));
}
float3 trussCorner(uint k,float3 U,float3 V,float w){k%=4;return ((k==0||k==3)?-1:1)*U*w*.5+(k<2?-1:1)*V*w*.5;}
uint trussBays(SsMember m){return clamp((uint)ceil(length(m.b.xyz-m.a.xyz)/(m.a.w*1.15)),1u,15u);}
Tube trussTube(SsMember m,uint t){
 Tube o=(Tube)0;if(m.b.w<.5||m.up.w>.5)return o;
 float3 a=m.a.xyz,b=m.b.xyz,D,U,V;trussFrame(m,D,U,V);float w=m.a.w-.05,L=length(b-a);   // chord centres: F34's 290 mm less one 50 mm chord
 if(round(m.b.w)==KIND_BLOCK){if(t>=12)return o;
  // the cube's edges: four along each axis
  uint ax=t/4,k=t%4;float3 c=(a+b)*.5,e[3]={D,V,U};float h=w*.5;
  float3 s=e[(ax+1)%3]*((k&1)?h:-h)+e[(ax+2)%3]*((k&2)?h:-h);
  o.a=float4(c+s-e[ax]*h,.025);o.b=float4(c+s+e[ax]*h,0);return o;}
 uint bays=trussBays(m);
 if(t<4){float3 c=trussCorner(t,U,V,w);o.a=float4(a+c,.025);o.b=float4(b+c,0);}
 else if(t<64){uint f=(t-4)/15,q=(t-4)%15;if(q>=bays)return o;
  float3 c0=trussCorner(f,U,V,w),c1=trussCorner(f+1,U,V,w);if(q%2==1){float3 x=c0;c0=c1;c1=x;}
  o.a=float4(lerp(a,b,(float)q/bays)+c0,.01);o.b=float4(lerp(a,b,(float)(q+1)/bays)+c1,0);}
 else if(t<72){uint k=(t-64)%4;float3 e=t<68?a:b;o.a=float4(e+trussCorner(k,U,V,w),.01);o.b=float4(e+trussCorner(k+1,U,V,w),0);}
 return o;
}
