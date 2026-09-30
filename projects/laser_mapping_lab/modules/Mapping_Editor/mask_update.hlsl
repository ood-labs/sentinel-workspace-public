// Applies the canvas pass's one-cook mask operation to the durable zones buffer.
// C[35] = (op, mask index, arg, 0), C[36] = its vector (scanner units).
//   1 create (arg = kind; rect in C36, or a polygon's first point in C36.xy)
//   2 set rect | 3 toggle Block/Only-In | 4 toggle on | 5 delete
//   6 append a polygon point | 7 insert a point after vertex arg | 8 move by C36.xy
//   9 set vertex arg | 10 set angle (C36.x)
RWStructuredBuffer<float4> M:register(u0);
StructuredBuffer<float4> C:register(t0);
#include "masks.hlsli"
uint pt(uint j,uint i){return MASK_PT0+POLY_MAX*j+i;}
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID){
 if(M[0].y!=MASK_COOKIE){[loop]for(uint k=0;k<MASK_PT0+POLY_MAX*MASK_MAX;k++)M[k]=0;M[0]=float4(0,MASK_COOKIE,0,0);}
 uint n=maskCount();
 // Persistent buffers can arrive with garbage: never keep a record that is not finite.
 [loop]for(uint s=0;s<n;s++)if(!all(isfinite(M[1+2*s]))||!all(isfinite(M[2+2*s]))){M[1+2*s]=0;M[2+2*s]=0;}
 int op=(int)C[35].x;uint j=(uint)C[35].y,arg=(uint)C[35].z;float4 v=C[36];
 if(!all(isfinite(v)))return;
 if(op==1&&j==n&&n<MASK_MAX){
  M[1+2*j]=float4(arg,0,1,0);
  if(arg==2){M[2+2*j]=float4(1,0,0,0);M[pt(j,0)]=float4(v.xy,0,0);}
  else M[2+2*j]=float4(v.xy,abs(v.zw));
  M[0].x=n+1;return;
 }
 if(j>=n)return;
 float4 info=M[1+2*j];bool poly=info.x>1.5;uint np=poly?polyCount(j):0;
 if(op==2&&!poly)M[2+2*j]=float4(v.xy,abs(v.zw));
 if(op==3)M[1+2*j].y=info.y<.5?1:0;
 if(op==4)M[1+2*j].z=info.z<.5?1:0;
 if(op==6&&poly&&np<POLY_MAX){M[pt(j,np)]=float4(v.xy,0,0);M[2+2*j].x=np+1;}
 if(op==7&&poly&&np<POLY_MAX&&arg<np){
  [loop]for(uint k=np;k>arg+1;k--)M[pt(j,k)]=M[pt(j,k-1)];
  M[pt(j,arg+1)]=float4(v.xy,0,0);M[2+2*j].x=np+1;
 }
 if(op==8){if(poly){[loop]for(uint k=0;k<np;k++)M[pt(j,k)].xy+=v.xy;}else M[2+2*j].xy+=v.xy;}
 if(op==9&&poly&&arg<np)M[pt(j,arg)]=float4(v.xy,0,0);
 if(op==10&&!poly)M[1+2*j].w=v.x;
 if(op==5){
  [loop]for(uint k=j;k+1<n;k++){
   M[1+2*k]=M[3+2*k];M[2+2*k]=M[4+2*k];
   [loop]for(uint i=0;i<POLY_MAX;i++)M[pt(k,i)]=M[pt(k+1,i)];
  }
  M[1+2*(n-1)]=0;M[2+2*(n-1)]=0;[loop]for(uint i=0;i<POLY_MAX;i++)M[pt(n-1,i)]=0;
  M[0].x=n-1;
 }
}
