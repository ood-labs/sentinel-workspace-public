RWTexture2D<float4> OutputUAV : register(u0);

float ss_line(float d, float w) { return 1.0 - smoothstep(w, w * 2.5, abs(d)); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float phase = slit_phase * 6.2831853 + _Time * scan_speed;
    float n = max(4.0, slice_count);
    float band = floor(uv.y * n);
    float bandUv = (band + 0.5) / n;
    float sweep = sin(phase * 0.71 + band * 1.37) * shear;
    float xOffset = (bandUv - 0.5) * shear * 0.55 + sin(phase + band * 0.43) * 0.045 * shear;
    float2 sampleUv = saturate(float2(uv.x + xOffset, bandUv));
    float3 source = _Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb;
    float neighboring = dot(_Tex0.SampleLevel(LinearSampler, saturate(float2(uv.x - xOffset * 0.7, uv.y)), 0).rgb, float3(0.299, 0.587, 0.114));
    float slicePulse = 0.65 + 0.35 * sin(phase * 1.3 + band * 0.9);
    float seam = ss_line(frac(uv.y * n) - 0.5, slice_height * 0.12) * seam_gain;
    float edge = ss_line(uv.x - frac(0.5 + phase * 0.055 + band * 0.017), 0.006) * (0.35 + neighboring);
    float3 ink = source * (0.42 + 0.24 * slicePulse) + slice_color * seam * 0.45;
    ink += accent_color * (edge * 0.72 + seam * 0.16 * step(0.7, frac(band * 0.31)));
    float3 outCol = lerp(source * 0.18 + dark_color * 0.3, ink, slit_mix);
    outCol += slice_color * ss_line(uv.y - 0.5, 0.003) * 0.18;
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
