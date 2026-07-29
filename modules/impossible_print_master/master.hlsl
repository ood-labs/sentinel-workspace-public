RWTexture2D<float4> OutputUAV : register(u0);

float hash_master(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;

    float3 center = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 blur =
        _Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv + float2(0, texel.y), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv - float2(0, texel.y), 0).rgb;
    blur *= 0.25;
    float3 col = center + (center - blur) * edge_recovery;

    float luma = dot(col, float3(0.299, 0.587, 0.114));
    col = lerp(luma.xxx, col, saturation);
    col = (col - 0.5) * contrast + 0.5 + paper_lift;

    float3 ink = 1.0 - saturate(col);
    float totalInk = ink.r + ink.g + ink.b;
    ink *= min(1.0, ink_limit / max(totalInk, 0.001));
    col = 1.0 - ink;

    float2 dotUv = frac((float2)tid.xy / max(screen_pitch, 1.0)) - 0.5;
    float dotField = smoothstep(0.30, 0.10, length(dotUv));
    float darkMask = smoothstep(0.72, 0.18, luma);
    col -= dotField * darkMask * screen_gain;

    float grain = hash_master(dot((float2)tid.xy, float2(0.0137, 0.0719))) - 0.5;
    col += grain * master_grain;

    float2 edge = min(uv, 1.0 - uv);
    float trim = smoothstep(trim_width + texel.x * 2.0, trim_width, min(edge.x, edge.y));
    col = lerp(col, trim_color, trim * trim_gain);

    float2 corner = min(uv, 1.0 - uv);
    float cropH = smoothstep(1.4 / _Resolution.y, 0.0, abs(corner.y - crop_inset)) *
                  step(corner.x, crop_length);
    float cropV = smoothstep(1.4 / _Resolution.x, 0.0, abs(corner.x - crop_inset)) *
                  step(corner.y, crop_length);
    col = lerp(col, crop_color, max(cropH, cropV) * crop_gain);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}

