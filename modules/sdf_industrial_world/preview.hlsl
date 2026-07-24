RWTexture2D<float4> OutputUAV : register(u0);
struct Part { float4 transform_a; float4 transform_b; float4 rotation; float4 meta; };
StructuredBuffer<Part> Parts : register(t0);

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px=DTid.xy; if(px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv=((float2)px+0.5)/_Resolution.xy;
    float2 p=(uv-0.5)*float2(5.2,2.8);
    float3 col=float3(0.006,0.008,0.011);
    float2 q=p;
    float base=smoothstep(0.08,0.0,abs(q.y+1.12));
    col+=base*float3(0.17,0.20,0.24);
    for(int i=0;i<24;i++) {
        Part a=Parts[i];
        float2 c=a.transform_a.xy*float2(1.0,0.82);
        float2 e=max(a.transform_b.xy*float2(1.0,0.82),float2(0.012,0.012));
        float2 d=abs(q-c)-e;
        float box=length(max(d,0.0))+min(max(d.x,d.y),0.0);
        float stroke=smoothstep(0.018,0.0,box);
        float3 tint=(a.rotation.w>2.5)?float3(0.72,0.22,0.06):float3(0.24,0.34,0.45);
        col+=stroke*tint*(a.meta.w>0.5?0.8:0.25);
    }
    float scan=smoothstep(0.02,0.0,abs(frac(p.y*0.42+_Time*0.08)-0.5));
    col+=scan*float3(0.035,0.05,0.07);
    OutputUAV[px]=float4(saturate(col),1.0);
}
