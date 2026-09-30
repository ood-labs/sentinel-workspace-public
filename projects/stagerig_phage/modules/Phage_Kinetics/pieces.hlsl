// Posed pixel-bar pieces: a=(xyz, u0) b=(xyz, u1) n=(facing, bar) w=(length, family, valid, piece).
// u runs 0..1 along the whole bar by length, so content flows continuously across pieces.
StructuredBuffer<float4> DesignIn:register(t0);
StructuredBuffer<float4> A:register(t1);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
#include "kin_common.hlsli"
struct PhPiece{float4 a;float4 b;float4 n;float4 w;};
RWStructuredBuffer<PhPiece> Q:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=PH_BARS*PH_BAR_SEGS)return;
 PhPiece q=(PhPiece)0;uint b=i/PH_BAR_SEGS,k=i%PH_BAR_SEGS;uint n=phBarSegCount(b);
 if(_Data0_Count>=17&&DesignIn[16].w==260929&&k<n){
  PhDesign D=phLoad();PhPose P=PH_POSE_FROM(A);float total=0,before=0,len=0;float3 a,c,nn,a0,c0,n0;
  for(uint j=0;j<n;j++){phBarPiece(D,P,b,j,a,c,nn);float l=length(c-a);if(j<k)before+=l;if(j==k){len=l;a0=a;c0=c;n0=nn;}total+=l;}
  q.a=float4(a0,before/max(total,1e-4));q.b=float4(c0,(before+len)/max(total,1e-4));q.n=float4(n0,b);q.w=float4(len,phBarFamily(b),1,k);}
 Q[i]=q;}
