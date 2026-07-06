// abstract_comp: ordered poster compositor. BG is opaque, other inputs use alpha masks.

RWTexture2D<float4> OutputUAV : register(u0);

float4 tapLayer(Texture2D t, float2 uv)
{
    return t.SampleLevel(LinearSampler, uv, 0);
}

float3 over(float3 dst, float4 src, float gain)
{
    float a = saturate(src.a * gain);
    return lerp(dst, src.rgb * gain, a);
}

float3 screenAdd(float3 dst, float4 src, float gain)
{
    float a = saturate(src.a * gain);
    float3 s = saturate(src.rgb * gain);
    return lerp(dst, 1.0 - (1.0 - dst) * (1.0 - s), a);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float4 bg = tapLayer(_Tex0, uv);
    float4 column = tapLayer(_Tex1, uv);
    float4 solids = tapLayer(_Tex2, uv);
    float4 ribbon = tapLayer(_Tex3, uv);
    float4 accents = tapLayer(_Tex4, uv);

    float3 col = bg.rgb * bg_gain;
    col = over(col, column, column_gain);
    col = over(col, solids, solids_gain);
    col = over(col, ribbon, ribbon_gain);
    col = over(col, accents, accents_gain);

    float asp = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(asp, 1.0);
    float vign = 1.0 - vignette * dot(p, p) * 0.18;
    col *= saturate(vign);
    col = pow(saturate(col * exposure), 1.0 / 2.2);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
