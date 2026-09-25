#include "../_shared/ui/sui3_text.hlsli"
#include "../_shared/show.hlsli"
StructuredBuffer<float4>S:register(t0);RWTexture2D<float4>OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;float2 p=id.xy;float3 c=float3(.025,.035,.05);float a=sui3Text(p,float2(20,15),2,82,69,65,82,32,84,79,32,70,82,79,78);for(uint i=0;i<48;i++){float2 q=float2(20+i*(w-40)/48.,80);if(all(p>=q)&&all(p<q+float2((w-40)/48.-3,50))){float rank=(i+.5)/48.;if(S[1].y>.5)rank=1-rank;c=float3(.1,.8,1)*klangPulse(S[0].x,rank,S[0].z,S[0].w)*S[0].y;}}OutputUAV[id.xy]=float4(lerp(c,1,a),1);}
