#include "geometry.hlsli"
StructuredBuffer<float4> Tree:register(t4);StructuredBuffer<float4> Plan:register(t5);
RWStructuredBuffer<Scan> O:register(u0);
// masked: a blank piece cut out of a lit record (by a mask or the field edge). It is marked with
// meta.w = 2 so the finalize pass can replace each run of them with one direct, fast blank jump.
// joint: the Scan Signal joint flag (timing.z) for the joint at this piece's start: 0 Laser Out
// decides, 1 smooth (no Corner Dwell), 2 corner. See the joint flags note in main.
void writePart(Scan r,float lo,float hi,float2 a,float2 b,float en,float ex,bool blank,bool masked,float joint,inout uint outAt){
 Scan q=r;float t0=lerp(lo,hi,en),t1=lerp(lo,hi,ex);q.timing.z=blank?0:joint;
 q.endpoints=clamp(float4(lerp(a,b,en),lerp(a,b,ex)),-1,1);
 q.color0=lerp(r.color0,r.color1,t0);q.color1=lerp(r.color0,r.color1,t1);
 q.timing.xy=float2(r.timing.x+r.timing.y*t0,r.timing.y*(t1-t0));q.meta.xy=lerp(r.meta.xx,r.meta.yy,float2(t0,t1));
 if(blank){q.timing.w=1;q.color0=q.color1=0;}if(masked)q.meta.w=2;O[outAt++]=q;
}
[numthreads(32,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;
 if(i==0){Scan h=(Scan)0;h.endpoints=float4(0,.025,30000,0);if(SOURCE_COUNT>0)h=SOURCE[0];h.endpoints.x=Plan[0].w<2?Plan[0].y:0;h.color0.x=Plan[0].w<2?1:0;O[0]=h;}
 if(i>=1023||i>=(uint)Plan[0].x||Plan[0].w>=2)return;
 Scan r=SOURCE[i+1];uint outAt=(uint)Plan[i+4].x,node=1,steps=0,bit=1u<<(uint)Plan[0].z;
 [loop]while(node>0&&steps++<2047){float4 v=Tree[i*2048+node];
  if(((uint)v.z&bit)!=0){node*=2;continue;}
  float2 a=at(r,v.x),b=at(r,v.y);
  if(r.timing.w>.5)writePart(r,v.x,v.y,a,b,0,1,true,false,0,outAt);
  else{
   // Lit where the chord is in the field and the zoning masks allow it, blanked everywhere else.
   // Joint flags: the record's own start keeps the producer's flag. A joint this pass makes by
   // subdividing the record (a piece starting inside it) is smooth, as it lies on the record's
   // own warped path. A piece that starts where a mask or the field edge cut it gets no flag.
   float cut[CUT_MAX+1];bool lit[CUT_MAX];uint np=chordPieces(a,b,cut,lit);
   [loop]for(uint p=0;p<np;p++){
    float joint=p>0?0:(v.x<=0?r.timing.z:1);
    writePart(r,v.x,v.y,a,b,cut[p],cut[p+1],!lit[p],!lit[p],joint,outAt);
   }
  }
  node=nextNode(node);
 }
}
