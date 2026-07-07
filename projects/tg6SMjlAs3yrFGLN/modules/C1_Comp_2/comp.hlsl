// c1_comp: opaque BG + premultiplied metallic hero with reference-style vignette and gamma.
RWTexture2D<float4> OutputUAV : register(u0);

float3 over(float3 dst, float4 src, float gain)
{
    float a = saturate(src.a * gain);
    float3 pr = src.rgb * gain;
    return pr + dst * (1.0 - a);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float4 bg = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float4 hero = _Tex1.SampleLevel(LinearSampler, uv, 0);

    float3 col = bg.rgb * bg_gain;
    col = over(col, hero, hero_gain);

    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    col *= 1.0 - vignette * dot(p, p) * 0.26;
    col = pow(saturate(col * exposure), 1.0 / gamma_value);

    OutputUAV[px] = float4(saturate(col), 1.0);
}
