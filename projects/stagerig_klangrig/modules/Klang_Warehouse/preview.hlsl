struct Architecture{float4 center,extent,surface,rotation;};StructuredBuffer<Architecture>A:register(t0);RWTexture2D<float4>OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint w,h;OutputUAV.GetDimensions(w,h);if(id.x>=w||id.y>=h)return;float2 uv=(id.xy+.5)/float2(w,h);bool elevation=uv.y>.67;float2 p=elevation?float2((uv.x-.5)*width*1.15,(1-uv.y)/.30*height+floor_level):float2((uv.x-.5)*width*1.15,(uv.y/.64-.5)*length*1.12);float3 c=float3(.018,.025,.035);
for(uint j=0;j<256;j++){Architecture a=A[j];if(a.extent.w<.5)continue;if(!elevation&&a.center.w==3)continue;float2 center=elevation?a.center.xy:a.center.xz,e=elevation?a.extent.xy:a.extent.xz;
float2 q=abs(p-center)-e;if(max(q.x,q.y)<0){if(elevation&&a.center.w==1&&a.extent.y>2&&a.extent.x>1&&min(abs(q.x),abs(q.y))>.1)continue;c=a.center.w==0?float3(.045,.055,.065):a.center.w==2?float3(.27,.43,.52):float3(.40,.47,.49);}}
if(abs(uv.y-.66)<.004)c=float3(.14,.45,.5);OutputUAV[id.xy]=float4(c,1);}
