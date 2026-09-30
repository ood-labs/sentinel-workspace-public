#include "assembly_types.hlsli"
// Truss expansion shared by the tube pass and the preview (the preview draws the real tubes).
void trussFrame(PhMember m,out float3 D,out float3 U,out float3 V){
 D=normalize(m.b.xyz-m.a.xyz);float3 r=m.up.xyz-D*dot(m.up.xyz,D);
 if(dot(r,r)<1e-5)r=abs(D.y)<.9?float3(0,1,0):float3(1,0,0);
 V=normalize(r);U=normalize(cross(V,D));
}
float3 trussCorner(uint k,float3 U,float3 V,float w){k%=4;return ((k==0||k==3)?-1:1)*U*w*.5+(k<2?-1:1)*V*w*.5;}
Tube trussTube(PhMember m,uint t){
 Tube o=(Tube)0;if(m.b.w<.5||m.up.w>.5)return o;
 float3 a=m.a.xyz,b=m.b.xyz,D,U,V;trussFrame(m,D,U,V);float w=m.a.w,L=length(b-a);
 uint bays=clamp((uint)ceil(L/(w*1.15)),1u,15u);float mat=m.b.w==11?1:0;
 if(t<4){float3 c=trussCorner(t,U,V,w);o.a=float4(a+c,w*.042);o.b=float4(b+c,mat);}
 else if(t<64){uint f=(t-4)/15,q=(t-4)%15;if(q>=bays)return o;
  float3 c0=trussCorner(f,U,V,w),c1=trussCorner(f+1,U,V,w);if(q%2==1){float3 x=c0;c0=c1;c1=x;}
  o.a=float4(lerp(a,b,(float)q/bays)+c0,w*.019);o.b=float4(lerp(a,b,(float)(q+1)/bays)+c1,mat);}
 else if(t<72){uint k=(t-64)%4;float3 e=t<68?a:b;o.a=float4(e+trussCorner(k,U,V,w),w*.026);o.b=float4(e+trussCorner(k+1,U,V,w),mat);}
 return o;
}
