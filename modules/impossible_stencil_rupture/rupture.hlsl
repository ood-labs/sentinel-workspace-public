RWTexture2D<float4> OutputUAV : register(u0);

float sr_line(float d, float w) { return 1.0 - smoothstep(w, w * 2.5, abs(d)); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float phase = rupture_phase * 6.2831853 + _Time * cut_speed;
    float coord = uv.x + (uv.y - 0.5) * slant + sin(phase * 0.63) * 0.08;
    float band = frac(coord * stripe_count + phase * 0.17);
    float threshold = saturate(stripe_width);
    float keep = smoothstep(threshold - 0.035, threshold + 0.035, band);
    float jag = sin(uv.y * 37.0 + phase * 1.4) * 0.045 + sin(uv.y * 91.0 - phase) * 0.018;
    keep *= step(0.18, frac(coord * stripe_count * 0.37 + jag + phase * 0.05));
    float2 survivorUv = saturate(uv + float2(jag * slant, jag));
    float3 src = _Tex0.SampleLevel(LinearSampler, survivorUv, 0).rgb;
    float edge = sr_line(band - threshold, 0.022 + abs(jag) * 0.3) * edge_gain;
    float cut = 1.0 - keep;
    float3 ink = src * (0.22 + keep * survivor * 0.88) + accent_color * edge * 1.25;
    ink = lerp(ink, dark_color, cut * rupture_mix);
    ink += accent_color * sr_line(coord * stripe_count + phase * 0.17, 0.011) * 0.22;
    OutputUAV[tid.xy] = float4(saturate(ink), 1.0);
}
