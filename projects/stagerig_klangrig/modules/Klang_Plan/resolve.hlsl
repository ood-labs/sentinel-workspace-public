
#include "layout.hlsli"
StructuredBuffer<float4>E:register(t0);RWStructuredBuffer<RigRecord>O:register(u0);
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 RigRecord r=(RigRecord)0;r.a=float4(float3(0,spine_height,-spine_length*.5)+E[4].xyz,1);r.b=float4(float3(0,spine_height,spine_length*.5)+E[4].xyz,1);r.shape=float4(truss_width,led_width,spine_count,0);r.meta=float4(0,0,0,1);O[0]=r;
 for(uint w=0;w<12;w++)for(uint leg=0;leg<4;leg++){
 float3 a=wingPoint(w,leg),b=wingPoint(w,(leg+1)%4),pivot=wingPoint(w,0);float angle=radians(wing_angle)*(w%2==0?-1:1);float cs=cos(angle),sn=sin(angle);
 float3 da=a-pivot,db=b-pivot;da.xy=float2(cs*da.x-sn*da.y,sn*da.x+cs*da.y);db.xy=float2(cs*db.x-sn*db.y,sn*db.x+cs*db.y);
 r.a=float4(pivot+da+E[5+w].xyz+E[4].xyz,1);r.b=float4(pivot+db+E[5+w].xyz+E[4].xyz,1);r.shape=float4(truss_width,led_width,rowCount(w),leg);r.meta=float4(1+w*4+leg,w+1,w/4+1,w%2==0?-1:1);O[1+w*4+leg]=r;
 }
}
