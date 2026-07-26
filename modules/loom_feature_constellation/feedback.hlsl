RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float2 q = (uv - 0.5) * (1.0 + trail_zoom * 0.003) + 0.5;
    float3 nowCol = _Tex0.Load(int3(id.xy, 0)).rgb;
    float3 oldCol = _Tex1.SampleLevel(LinearSampler, saturate(q), 0).rgb;
    float keep = pow(saturate(trail_decay), _DeltaTime * 60.0);
    float3 woven = nowCol + oldCol * keep * 0.32;
    woven += oldCol.brg * trail_chroma * 0.006;
    OutputUAV[id.xy] = float4(min(woven, 6.0), 1.0);
}
