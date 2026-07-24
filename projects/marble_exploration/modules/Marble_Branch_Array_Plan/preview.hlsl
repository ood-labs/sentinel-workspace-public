RWTexture2D<float4> OutputUAV : register(u0);
struct Part { float4 transform_a; float4 transform_b; float4 rotation; float4 meta; };
StructuredBuffer<Part> Parts : register(t0);

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px=DTid.xy; if(px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv=((float2)px+0.5)/_Resolution.xy;
    float2 p=(uv-0.5)*float2(3.4,2.0);
    float3 col=float3(0.004,0.006,0.009);
    float grid=smoothstep(0.012,0.0,abs(frac(p.x*0.8)-0.5))+smoothstep(0.012,0.0,abs(frac(p.y*0.8)-0.5));
    col+=grid*float3(0.018,0.025,0.035);
    for(int i=0;i<48;i++) {
        Part q=Parts[i];
        float2 c=q.transform_a.xy*float2(1.0,0.72);
        float2 e=max(q.transform_b.xy*float2(1.0,0.72),float2(0.008,0.008));
        float2 d=abs(p-c)-e;
        float box=length(max(d,0.0))+min(max(d.x,d.y),0.0);
        float stroke=smoothstep(0.014,0.0,box);
        float3 tint=(q.transform_a.w==3)?float3(0.8,0.16,0.035):float3(0.18,0.34,0.52);
        col+=stroke*tint*(q.transform_a.w==3?0.36:0.82);
    }
    float orbit=smoothstep(0.02,0.0,abs(length(p/float2(1.08,0.72))-0.92));
    col+=orbit*float3(0.25,0.08,0.025);
    OutputUAV[px]=float4(saturate(col),1.0);
}
