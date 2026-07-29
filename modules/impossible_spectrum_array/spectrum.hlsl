RWTexture2D<float4> OutputUAV : register(u0);
float sp_line(float d, float w) { return 1.0 - smoothstep(w, w * 2.5, abs(d)); }

[numthreads(8,8,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float phase = spectrum_phase * 6.2831853 + _Time * sweep_speed;
    float n = max(8.0, bar_count);
    float id = floor(uv.x * n);
    float cx = (id + 0.5) / n;
    float lum = dot(_Tex0.SampleLevel(LinearSampler, float2(cx, 0.5), 0).rgb, float3(0.299, 0.587, 0.114));
    float upper = 0.5 - lum * 0.42 * bar_gain;
    float lower = 0.5 + lum * 0.42 * bar_gain;
    float inside = step(upper, uv.y) * step(uv.y, lower);
    float local = frac(uv.x * n) - 0.5;
    float bar = sp_line(local, bar_width * 0.5) * inside;
    float baseGrid = sp_line(local, 0.014);
    float thresholdY = 0.5 + sin(phase + id * 0.37) * 0.22;
    float threshold = sp_line(uv.y - thresholdY, px.y * 3.0);
    float baseline = sp_line(uv.y - 0.5, px.y * 2.0);
    float pulse = 0.65 + 0.35 * sin(phase * 1.4 + id * 0.71);
    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 ink = dark_color + bar_color * bar * (0.55 + 0.45 * pulse) + bar_color * baseGrid * 0.16;
    ink += bar_color * baseline * 0.28;
    ink += accent_color * threshold * threshold_gain;
    float3 outCol = lerp(source * 0.16 + dark_color * 0.3, ink, spectrum_mix);
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
