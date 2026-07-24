RWTexture2D<float4> OutputUAV : register(u0);
struct GlitchField { float4 global_distortion; float4 slice_pattern; float4 fracture_pattern; float4 temporal_motion; };
StructuredBuffer<GlitchField> Field : register(t0);

float hash21(float2 p) { p=frac(p*float2(123.34,456.21)); p+=dot(p,p+45.32); return frac(p.x*p.y); }

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px=DTid.xy; if(px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv=((float2)px+0.5)/_Resolution.xy;
    float2 p=(uv-0.5)*float2(2.0,1.12);
    GlitchField f=Field[0];
    float t=f.temporal_motion.x;
    float3 col=float3(0.006,0.008,0.011);
    float slab=smoothstep(0.055,0.0,abs(abs(p.x+sin(p.y*5.0+t)*0.035)-0.42));
    col+=float3(0.07,0.11,0.15)*slab;
    float band=abs(frac((p.y+f.temporal_motion.y*0.12)*f.slice_pattern.y*0.5)-0.5);
    float glitches=smoothstep(f.slice_pattern.z,0.0,band)*step(0.12,hash21(floor((p+float2(t*0.2,0))*18.0)+f.slice_pattern.w));
    float cuts=step(0.74,hash21(floor(p*float2(17.0,25.0))+f.fracture_pattern.w));
    col+=glitches*float3(0.48,0.62,0.82)*(0.25+f.slice_pattern.x);
    col+=cuts*glitches*float3(0.95,0.22,0.06)*0.42;
    float ring=smoothstep(0.015,0.0,abs(length(p/float2(0.45,0.78))-0.78));
    col+=ring*float3(0.18,0.24,0.32);
    OutputUAV[px]=float4(saturate(col),1.0);
}
