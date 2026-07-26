RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float2 rotate2(float2 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);

    float3 current = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float lumL = luminance(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb);
    float lumR = luminance(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb);
    float lumU = luminance(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb);
    float lumD = luminance(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb);
    float2 gradient = float2(lumR - lumL, lumD - lumU);
    float edge = length(gradient);

    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float frameRotation = rotation_rate * _DeltaTime;
    float frameScale = exp(-zoom_drift * _DeltaTime);
    float2 prevP = rotate2(p, frameRotation) * frameScale;

    float2 tangent = float2(-gradient.y, gradient.x);
    prevP -= tangent * smear * _DeltaTime * 60.0;
    float2 prevUv = prevP / float2(aspect, 1.0) + 0.5;

    float border = step(0.0, prevUv.x) * step(prevUv.x, 1.0)
                 * step(0.0, prevUv.y) * step(prevUv.y, 1.0);
    float3 memory = _Tex1.SampleLevel(LinearSampler, saturate(prevUv), 0).rgb * border;
    float keep = pow(saturate(persistence), _DeltaTime * 60.0);

    float sourceLum = luminance(current);
    float gate = smoothstep(threshold, threshold + 0.16, sourceLum + edge * 1.4);
    float3 sourceInk = current * gate;
    sourceInk += edge * gate * float3(0.42, 0.44, 0.43);

    float3 accumulated = memory * keep + sourceInk * injection * _DeltaTime * 60.0;
    accumulated = min(accumulated, float3(5.0, 5.0, 5.0));

    OutputUAV[pixel] = float4(accumulated, 1.0);
}
