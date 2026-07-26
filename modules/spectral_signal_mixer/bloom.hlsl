RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float2 t = bloom_radius / _Resolution.xy;
    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * 0.28;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(t.x,0)),0).rgb * 0.12;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv - float2(t.x,0)),0).rgb * 0.12;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0,t.y)),0).rgb * 0.12;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv - float2(0,t.y)),0).rgb * 0.12;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv + t),0).rgb * 0.06;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv - t),0).rgb * 0.06;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(t.x,-t.y)),0).rgb * 0.06;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(-t.x,t.y)),0).rgb * 0.06;
    OutputUAV[id.xy] = float4(c, 1.0);
}
