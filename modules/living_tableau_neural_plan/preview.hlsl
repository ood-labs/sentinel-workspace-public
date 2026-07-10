struct PrimitiveRecord { float2 p0; float2 p1; float3 color; float width; float kind; float group_id; float route_t; float active; };
StructuredBuffer<PrimitiveRecord> P : register(t0); RWTexture2D<float4> OutputUAV:register(u0);
float sdSeg(float2 p,float2 a,float2 b){float2 pa=p-a,ba=b-a;float t=saturate(dot(pa,ba)/max(dot(ba,ba),1e-7));return length(pa-ba*t);}
[numthreads(8,8,1)] void main(uint3 id:SV_DispatchThreadID){if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;float2 uv=((float2)id.xy+.5)/_Resolution.xy;float3 c=0;[loop]for(uint i=0;i<192;i++){PrimitiveRecord r=P[i];if(r.active<.5)continue;float d=r.kind<.5?sdSeg(uv,r.p0,r.p1):length(uv-r.p0);float k=saturate(1-d/max(r.width*2,1e-4));c=max(c,r.color*k);}OutputUAV[id.xy]=float4(c,1);}
