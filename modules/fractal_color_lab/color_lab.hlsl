RWTexture2D<float4> OutputUAV : register(u0);

float3 shift(float2 uv, float2 dir)
{
    return _Tex0.SampleLevel(LinearSampler, saturate(uv + dir), 0).rgb;
}

float3 poster(float3 c, float steps)
{
    return floor(c * steps + 0.5) / max(steps, 1.0);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 centered = uv - 0.5;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = centered * float2(aspect, 1.0);
    float d = length(p);
    float2 dir = normalize(p + 1e-5) * chroma * 0.004;

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 rgb;
    rgb.r = shift(uv, dir * (1.0 + d)).r;
    rgb.g = base.g;
    rgb.b = shift(uv, -dir * (1.3 + d)).b;

    float scan = 0.94 + 0.06 * sin((uv.y * _Resolution.y + _Time * 80.0) * 3.14159);
    float ring = smoothstep(0.7, 0.05, abs(frac(d * 12.0 - _Time * 0.18) - 0.5));
    rgb += ring * accent * float3(0.18, 0.08, 0.28);
    rgb = lerp(rgb, poster(rgb, poster_steps), posterize);
    rgb = lerp(base, rgb * scan, mix);
    rgb *= smoothstep(1.05, 0.22, d);
    rgb += float3(0.015, 0.010, 0.020);

    OutputUAV[pixel] = float4(saturate(rgb), 1.0);
}
