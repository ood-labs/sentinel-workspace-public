// HDR scene (PHAGE's hdr_scene): surfaces and their deck reflections attenuated through the haze, plus the
// half-resolution washes and deck light (a 4-tap tent hides the upsample), plus the full-resolution beams.
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    float2 uv = ((float2)id.xy + 0.5) / float2(w, h);
    float4 s = _Tex0.SampleLevel(PointSampler, uv, 0);
    float depth = s.a > 0.0 ? s.a : 60.0;
    float3 scene = s.a > 0.0 ? s.rgb : float3(0.0006, 0.0007, 0.0009);
    uint vw, vh;
    _Tex1.GetDimensions(vw, vh);
    float2 o = 0.75 / float2(vw, vh);
    float3 vol = 0.25 * (_Tex1.SampleLevel(LinearSampler, uv + float2(o.x, o.y), 0).rgb + _Tex1.SampleLevel(LinearSampler, uv + float2(-o.x, o.y), 0).rgb
                       + _Tex1.SampleLevel(LinearSampler, uv + float2(o.x, -o.y), 0).rgb + _Tex1.SampleLevel(LinearSampler, uv - o, 0).rgb);
    float3 beams = _Tex2.SampleLevel(PointSampler, uv, 0).rgb;
    float3 refl = _Tex3.SampleLevel(PointSampler, uv, 0).rgb;
    OutputUAV[id.xy] = float4((scene + refl) * exp(-haze * depth) + vol + beams, 1.0);
}
