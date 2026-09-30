#include "../_shared/scan.hlsli"
StructuredBuffer<Scan> S:register(t0);RWStructuredBuffer<Scan> O:register(u0);
// A blank jump needs a settle plus its travel at a speed the scanner can actually hold. Timing a
// jump faster than the scanner's step limit makes Laser Out stretch the whole cycle to catch up.
static const float JUMP_SETTLE_MS=0.15;
float jumpSec(float len){return (JUMP_SETTLE_MS+len/max(jump_speed,.05))*1e-3;}
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 Scan h=S[0];uint n=min((uint)h.endpoints.x,1023u);bool ok=h.color0.x>.5;
 [loop]for(uint c=1;c<=n;c++){Scan r=S[c];ok=ok&&all(isfinite(r.endpoints))&&all(abs(r.endpoints)<=1)&&r.meta.w!=0;}
 // 1. Hidden geometry costs no drawing time. A chain of consecutive blank records that contains
 //    any piece hidden by a mask or the field edge (meta.w 2) is replaced by ONE direct blank jump
 //    from where the beam leaves the visible path to where it comes back, so a whole hidden line,
 //    and the jumps into and out of it, cost a single jump. Chains with nothing hidden in them are
 //    the content's own blanks (jumps, corner stops, padding) and are kept.
 uint m=0,i=1;bool clipped=false;
 [loop]while(i<=n){
  Scan r=S[i];
  if(r.timing.w<.5){m++;O[m]=r;i++;continue;}
  uint j=i;bool hidden=false;
  [loop]while(j<=n&&S[j].timing.w>.5){hidden=hidden||S[j].meta.w>1.5;j++;}
  clipped=clipped||hidden;
  if(hidden){
   Scan q=S[i];q.endpoints.zw=S[j-1].endpoints.zw;q.meta.w=1;q.meta.y=S[j-1].meta.y;
   q.timing.y=jumpSec(length(q.endpoints.zw-q.endpoints.xy));m++;O[m]=q;
  }else{
   // The content's own jumps are only ever lengthened, to what the scanner can hold.
   [loop]for(uint k=i;k<j;k++){Scan b=S[k];float L=length(b.endpoints.zw-b.endpoints.xy);if(L>1e-6)b.timing.y=max(b.timing.y,jumpSec(L));m++;O[m]=b;}
  }
  i=j;
 }
 float total=0,fixed=0;
 [loop]for(uint i=1;i<=m;i++){Scan r=O[i];float d=length(r.endpoints.zw-r.endpoints.xy);if(r.timing.w<.5&&d>1e-9)total+=d;else fixed+=r.timing.y;}
 bool retime=h.color1.w>.5&&total>1e-9;float movingTime=max(h.endpoints.y-fixed,.001);
 // 2. Begin continuous cycles with their existing blank return. At the cycle boundary, float
 //    rounding in the native sampler can omit the final blank endpoint and light the remaining
 //    travel into the first stroke. Moving the return to time zero makes its endpoint an internal
 //    interval boundary. This is a cyclic rotation: no added points, changed geometry, or blank time.
 if(retime&&m>1&&O[m].timing.w>.5&&O[1].timing.w<.5&&length(O[m].endpoints.zw-O[1].endpoints.xy)<1e-6){
  Scan last=O[m];[loop]for(uint i=m;i>1;i--)O[i]=O[i-1];O[1]=last;
 }
 // 3. Lay the records end to end in time.
 float at=0;
 [loop]for(uint i=1;i<=m;i++){Scan r=O[i];if(retime){float d=length(r.endpoints.zw-r.endpoints.xy);if(r.timing.w<.5&&d>1e-9)r.timing.y=movingTime*d/total;}r.timing.x=at;at+=r.timing.y;O[i]=r;}
 // 4. A mask that hides most of a shape shortens its cycle, which concentrates the beam on what
 //    is left and runs it hot. Pad any cycle shorter than Min Cycle with blanked time in place.
 float minC=max(min_cycle_ms,0)*1e-3;
 if(m>0&&m<1023&&at<minC){clipped=true;Scan p=O[m];p.endpoints=p.endpoints.zwzw;p.color0=p.color1=float4(0,0,0,1);p.timing=float4(at,minC-at,0,1);p.meta.xy=p.meta.yy;m++;O[m]=p;at=minC;}
 [loop]for(uint z=1;z<=m;z++)O[z].meta.z=at;
 // The header's closed-loop flag (timing.z 1: the cycle is one lit loop, so its seam is smooth)
 // holds only while nothing was hidden, clipped or padded.
 if(clipped)h.timing.z=0;
 h.endpoints.y=m>0?at:h.endpoints.y;h.endpoints.x=ok?m:0;h.color0.x=ok?1:0;O[0]=h;
}
