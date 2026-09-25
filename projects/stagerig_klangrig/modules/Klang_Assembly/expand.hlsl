
#include "../_shared/rig.hlsli"
struct Tube{float4 a;float4 b;float4 cutA;float4 cutB;};
StructuredBuffer<RigRecord>R:register(t0);StructuredBuffer<MountRecord>M:register(t1);RWStructuredBuffer<Tube>T:register(u0);
Tube tube(float3 a,float3 b,float radius,float material){Tube t=(Tube)0;t.a=float4(a,radius);t.b=float4(b,material);return t;}
float3 corner(uint c,float3 U,float3 V,float width){return ((c==0||c==3)?-1:1)*U*width*.5+(c<2?-1:1)*V*width*.5;}
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=12832)return;Tube t=(Tube)0;
 if(i<12544){uint n=i/256,k=i%256;RigRecord r=R[n];float3 a=r.a.xyz,b=r.b.xyz,D=normalize(b-a);float L=length(b-a);float3 U=normalize(cross(abs(D.y)<.9?float3(0,1,0):float3(1,0,0),D)),V=cross(D,U);float width=r.shape.x;
 if(k<4)t=tube(a+corner(k,U,V,width),b+corner(k,U,V,width),.025,0);
 else if(k<244){uint f=(k-4)/60,q=(k-4)%60,bays=min(60u,max(1u,(uint)ceil(L/.65)));if(q<bays){float3 A=corner(f,U,V,width),B=corner((f+1)%4,U,V,width);if(q%2){float3 tmp=A;A=B;B=tmp;}t=tube(lerp(a,b,(float)q/bays)+A,lerp(a,b,(float)(q+1)/bays)+B,.009,0);}}
 else if(k<252){uint f=(k-244)%4;float3 end=k<248?a:b;t=tube(end+corner(f,U,V,width),end+corner((f+1)%4,U,V,width),.012,0);}
 else if(k<254){float3 end=k==252?a:b;t=tube(end,float3(end.x,suspension_height,end.z),.006,1);}
 }else{MountRecord m=M[i-12544];if(m.active>.5)t=tube(m.position,m.position+float3(0,.24,0),.018,0);}
 T[i]=t;}
