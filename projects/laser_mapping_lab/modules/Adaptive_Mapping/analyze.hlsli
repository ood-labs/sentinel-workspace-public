#include "geometry.hlsli"
// 2048 entries per source record: identity then a depth-10 dyadic tree.
RWStructuredBuffer<float4> Tree:register(u0);
[numthreads(32,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint i=tid.x;if(i>=1023)return;uint base=i*2048;
 if(SOURCE_COUNT==0||i>=(uint)SOURCE[0].endpoints.x||!calOK()){Tree[base]=0;return;}
 Scan r=SOURCE[i+1];float4 key=float4(r.timing.z,r.meta.xy,SOURCE[0].endpoints.x+1024*SOURCE[0].color0.y);
 bool history=all(Tree[base]==key);Tree[base]=key;
 uint node=1;uint iterations=0;
 [loop]while(node>0&&iterations++<2047){
  uint depth=(uint)firstbithigh(node),width=1u<<depth;
  float lo=(float)(node-width)/width,hi=lo+1.0/width;
  float err=0;if(mapping_mode==0&&r.timing.w<.5)err=deviation(r,lo,hi);
  uint old=history?(uint)Tree[base+node].z:0,mask=0;
  [unroll]for(uint level=0;level<12;level++)if(err>tolerance*exp2((float)level)*((old&(1u<<level))!=0?.5:1))mask|=1u<<level;
  if(node>1)mask&=(uint)Tree[base+node/2].z;
  uint hit=depth==10?mask:0;if(depth==10)mask=0;
  // w carries unresolved error at the depth limit, otherwise the geometric error.
  Tree[base+node]=float4(lo,hi,mask,hit>0?-max(err,1e-20):err);
  if(mask!=0){if(!history||(old==0)){Tree[base+node*2]=0;Tree[base+node*2+1]=0;}node*=2;}
  else node=nextNode(node);
 }
}
