#include "geometry.hlsli"
StructuredBuffer<float4> Tree:register(t4);
RWStructuredBuffer<float4> Counts:register(u0);
[numthreads(32,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint i=tid.x;if(i>=1023)return;
 [unroll]for(uint k=0;k<4;k++)Counts[i*4+k]=0;
 if(SOURCE_COUNT==0||i>=(uint)SOURCE[0].endpoints.x||!calOK())return;
 Scan r=SOURCE[i+1];uint totals[12];[unroll]for(uint k=0;k<12;k++)totals[k]=0;
 uint node=1,hits=0,steps=0;bool valid=all(isfinite(r.endpoints))&&all(isfinite(r.timing))&&all(isfinite(r.color0))&&all(isfinite(r.color1))&&all(isfinite(r.meta))&&r.meta.w!=0&&r.timing.x>=0&&r.timing.y>=0&&r.timing.x+r.timing.y<=SOURCE[0].endpoints.y+1e-6&&all(r.color0>=0)&&all(r.color0<=1)&&all(r.color1>=0)&&all(r.color1<=1);
 [loop]while(node>0&&steps++<2047){float4 v=Tree[i*2048+node];uint split=(uint)v.z,active=node==1?4095u:(uint)Tree[i*2048+node/2].z;
  uint leaf=active&~split;if(leaf!=0){valid=valid&&all(isfinite(float4(at(r,v.x),at(r,v.y))));uint n=pieceCount(r,v.x,v.y);[unroll]for(uint k=0;k<12;k++)if((leaf&(1u<<k))!=0)totals[k]+=n;}
  if(v.w<0)hits++;
  if(!isfinite(v.w))valid=false;
  node=split!=0?node*2:nextNode(node);
 }
 [unroll]for(uint k=0;k<3;k++)Counts[i*4+k]=float4(totals[k*4],totals[k*4+1],totals[k*4+2],totals[k*4+3]);
 Counts[i*4+3]=float4(hits,valid?1:0,0,0);
}
