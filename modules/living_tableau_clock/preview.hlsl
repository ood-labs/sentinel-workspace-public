struct SceneGlobals { float phase; float pulse_a; float pulse_b; float pulse_c; float pulse_d; float2 drift; float active; };
StructuredBuffer<SceneGlobals> SceneIn : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8,8,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    SceneGlobals s = SceneIn[0];
    float ring = smoothstep(0.012, 0.002, abs(length((uv-0.5)*float2(_Resolution.x/_Resolution.y,1))-0.27));
    float ang = atan2(uv.y-0.5, uv.x-0.5) / 6.28318530718 + 0.5;
    float tick = smoothstep(0.035, 0.0, abs(frac(ang-s.phase+0.5)-0.5)) * smoothstep(0.3,0.26,length(uv-0.5));
    float3 col = float3(0.02,0.04,0.05) + ring*float3(0.1,0.5,0.55) + tick*float3(1,0.3,0.08);
    OutputUAV[id.xy] = float4(col,1);
}
