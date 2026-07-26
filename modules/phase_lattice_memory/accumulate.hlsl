RWTexture2D<float4> OutputUAV : register(u0);

float2 rotate_about(float2 uv, float2 center, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    float2 p = uv - center;
    return center + float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
    float3 current = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float lumL = dot(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb, float3(0.299, 0.587, 0.114));
    float lumR = dot(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb, float3(0.299, 0.587, 0.114));
    float lumU = dot(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb, float3(0.299, 0.587, 0.114));
    float lumD = dot(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb, float3(0.299, 0.587, 0.114));
    float2 gradient = float2(lumR - lumL, lumD - lumU);
    float2 tangent = normalize(float2(-gradient.y, gradient.x) + float2(1e-5, 0.0));

    float2 center = float2(0.5, 0.5) + memory_core;
    float2 q = uv - tangent * texel * transport * 2.2;
    q = rotate_about(q, center, rotation_bias * 0.0018);
    float3 injected = current;

    if (memory_mode == 1)
    {
        float mirrored = center.x + abs(q.x - center.x);
        float pulse = sin((q.y - center.y) * 31.0 + _Time * 0.41) * texel.x * transport * 4.0;
        q.x = mirrored + pulse;
        q.y += sign(uv.x - center.x) * sin((q.x - center.x) * 19.0) * texel.y * transport * 2.5;

        float2 mirrorUv = float2(center.x + abs(uv.x - center.x), uv.y);
        float3 mirrorCurrent = _Tex0.SampleLevel(LinearSampler, clamp(mirrorUv, texel, 1.0 - texel), 0).rgb;
        injected = mirrorCurrent;
    }
    else if (memory_mode == 2)
    {
        float2 local = q - center;
        float scar = sin((local.x - local.y * 0.73) * 54.0 - _Time * 0.33);
        float scarStep = step(0.0, scar) * 2.0 - 1.0;
        q += float2(1.0, -0.63) * scarStep * texel * transport * 8.0;
        q = floor(q / (texel * float2(4.0, 2.0))) * (texel * float2(4.0, 2.0));

        float3 scarCurrent = _Tex0.SampleLevel(LinearSampler, clamp(q, texel, 1.0 - texel), 0).rgb;
        injected = max(current * 0.72, scarCurrent);
    }

    q = clamp(q, texel * 0.5, 1.0 - texel * 0.5);
    float4 previous = _Tex1.SampleLevel(LinearSampler, q, 0);

    float currentLum = dot(injected, float3(0.299, 0.587, 0.114));
    float deposit = smoothstep(deposit_gate, deposit_gate + 0.16, currentLum);
    float retained = saturate(previous.a * memory - erosion);

    float3 historical = max(previous.rgb * (memory - erosion * 0.45), 0.0);
    float3 fresh = injected * lerp(0.34, 1.0, deposit);
    float3 combined = max(fresh, historical);

    float redDominance = max(0.0, previous.r - max(previous.g, previous.b));
    float scarAccent = retained * (1.0 - deposit) * smoothstep(0.08, 0.42, redDominance);
    combined += scarAccent * float3(0.16, 0.012, 0.0);

    OutputUAV[pixel] = float4(saturate(combined), max(deposit, retained));
}
