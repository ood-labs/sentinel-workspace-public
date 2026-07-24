RWTexture2D<float4> OutputUAV : register(u0);
struct LightRecord { float4 position_radius; float4 color_intensity; float4 direction_type; };
StructuredBuffer<LightRecord> Lights : register(t0);

float3 lightColor(int i) {
    if (i == 0) return float3(1.0,0.58,0.25);
    if (i == 1) return float3(0.55,0.62,0.72);
    if (i < 4) return float3(1.0,0.28,0.10);
    return float3(0.86,0.48,0.20);
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px=DTid.xy; if(px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv=((float2)px+0.5)/_Resolution.xy;
    float2 p=(uv-0.5)*float2(2.1,1.25);
    float3 col=float3(0.012,0.014,0.017);
    float torso=length(p/float2(0.38,0.82));
    col += float3(0.18,0.17,0.15)*smoothstep(1.02,0.94,torso);
    col -= float3(0.16,0.10,0.07)*smoothstep(0.58,0.44,length(p/float2(0.13,0.48)));
    for(int i=0;i<8;++i){
        LightRecord l=Lights[i];
        float2 lp=l.position_radius.xy*0.28;
        float2 dir=normalize(l.direction_type.xy+float2(0.0001,0.0001));
        float marker=smoothstep(0.06,0.0,length(p-lp));
        float ray=abs((p-lp).x*dir.y-(p-lp).y*dir.x);
        float along=dot(p-lp,dir);
        float beam=smoothstep(0.025,0.002,ray)*step(0.0,along)*smoothstep(1.8,0.1,along);
        float3 c=lightColor(i);
        col += c*marker*(0.45+l.color_intensity.w*0.12);
        col += c*beam*0.08;
    }
    OutputUAV[px]=float4(saturate(col),1.0);
}
