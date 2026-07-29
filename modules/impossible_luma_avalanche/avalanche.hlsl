RWTexture2D<float4> OutputUAV : register(u0);

float la_hash(float2 p) {
    p = frac(p * float2(0.151, 0.311));
    p += dot(p, p.yx + 16.27);
    return frac(p.x * p.y * 28.13);
}

float la_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float t = avalanche_phase * 6.2831853 * avalanche_rate;
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float luma = dot(base, float3(0.299,0.587,0.114));

    float band = floor(uv.y * band_count);
    float bandHash = la_hash(float2(band, floor(avalanche_phase * 17.0)));
    float wave = sin(uv.y * 15.0 + t * 1.3) * 0.5 + cos(uv.y * 37.0 - t * 0.7) * 0.25;
    float displacement = (luma - 0.44) * avalanche_amount + wave * avalanche_amount * 0.22;
    displacement += (bandHash - 0.5) * tear_amount;
    displacement *= (0.60 + 0.40 * sin(t * 0.6 + band * 0.19));

    float2 shiftedUv = saturate(uv + float2(displacement, 0.0));
    float3 shifted = _Tex0.SampleLevel(LinearSampler, shiftedUv, 0).rgb;
    float2 echoUv = saturate(uv + float2(displacement * -0.46 + sin(t + uv.y * 5.0) * 0.012, 0.0));
    float3 echo = _Tex0.SampleLevel(LinearSampler, echoUv, 0).rgb;
    float3 col = lerp(base, lerp(shifted, echo, 0.28), avalanche_mix);

    float tears = la_line(uv.y * band_count + t * 0.22 + bandHash * 0.8, 0.018);
    float notches = la_line((uv.y * band_count * 0.53 - t * 0.13), 0.011);
    float gaps = saturate(tears * 0.48 + notches * 0.18) * avalanche_mix;
    col = lerp(col, dark_color, gaps * 0.66);

    float spark = la_line((uv.x + uv.y * 0.31 + t * 0.02) * 31.0 + bandHash, 0.009);
    float sparkMask = spark * saturate(abs(luma - 0.45) * 2.4) * avalanche_mix;
    col = lerp(col, accent_color, sparkMask * 0.38);
    col += (la_hash((float2)tid.xy + avalanche_phase * 47.0) - 0.5) * grain_gain * 0.014 * avalanche_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
