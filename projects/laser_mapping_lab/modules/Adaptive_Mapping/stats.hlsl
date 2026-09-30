#include "../_shared/scan.hlsli"
StructuredBuffer<float4> P0:register(t0);StructuredBuffer<Scan> A:register(t3);
RWStructuredBuffer<float4> O:register(u0);
// One laser: (input count, output count, status, look), (requested tol, effective tol,
// depth-limit hits, budget), (mapped length, cycle s, blank s, dwell s), (valid, mode, 0, 0).
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 float4 p=P0[0],t=P0[1];Scan h=A[0];
 float len=0,blank=0,dwell=0;[loop]for(uint i=1;i<=min((uint)h.endpoints.x,1023u);i++){Scan r=A[i];float d=length(r.endpoints.zw-r.endpoints.xy);if(r.timing.w>.5)blank+=r.timing.y;else{len+=d;if(d<1e-9)dwell+=r.timing.y;}}
 O[0]=float4(p.x,h.endpoints.x,h.color0.x<.5&&p.w<2?3:p.w,h.color0.y);O[1]=float4(t.xyz,record_budget);O[2]=float4(len,h.endpoints.y,blank,dwell);O[3]=float4(h.color0.x,mapping_mode,0,0);
}
