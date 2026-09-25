
#include "../_shared/rig.hlsli"
StructuredBuffer<RigRecord>R:register(t0);RWTexture2D<float4>OutputUAV:register(u0);
float lineDist(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),.0001)));}
float2 proj(float3 q){return float2(.5,.75)+float2(-q.z+q.x*.65,-q.y+q.x*.22)/float2(40,22);}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;float2 p=id.xy;float3 c=float3(.025,.035,.045);for(uint i=0;i<SEGMENTS;i++){RigRecord r=R[i];float2 a=proj(r.a.xyz)*float2(w,h),b=proj(r.b.xyz)*float2(w,h);float d=lineDist(p,a,b);float k=1-smoothstep(2,3,d);c=lerp(c,i==0?float3(.9,.75,.4):float3(.55,.72,.78),k);float3 end=float3(r.a.x,suspension_height,r.a.z);c=lerp(c,float3(.23,.3,.36),1-smoothstep(.3,1,lineDist(p,a,proj(end)*float2(w,h))));}OutputUAV[id.xy]=float4(c,1);}
