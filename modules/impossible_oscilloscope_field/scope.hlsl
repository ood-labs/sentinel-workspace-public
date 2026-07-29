RWTexture2D<float4> OutputUAV : register(u0);
float hashScope(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
float lineScope(float x, float width) { return 1.0 - smoothstep(width, width * 2.0, abs(frac(x) - 0.5)); }

 [numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float4 base = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float luma = dot(base.rgb, float3(0.299, 0.587, 0.114));
    float phase = scope_phase * 6.2831853;
    float t = phase + _Time * sweep_speed;
    float3 dark = dark_color;
    float3 ink = dark;
    float grid = (lineScope(uv.x * 16.0, px.x * 1.5) + lineScope(uv.y * 10.0, px.y * 1.5)) * grid_gain;
    ink += line_color * grid * 0.22;
    float traceAccum = 0.0;
    float3 traceCol = 0.0;
    [unroll] for (int i = 0; i < 8; i++) {
        float fi = (float)i;
        float active = step(fi + 0.5, trace_count);
        float band = 0.5 + (fi - 3.5) * 0.105;
        float2 sampleUv = float2(uv.x, saturate(band));
        float source = dot(_Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb, float3(0.299, 0.587, 0.114));
        float ripple = sin(uv.x * (8.0 + fi * 1.7) + t * (0.8 + fi * 0.11) + hashScope(float2(fi, 2.0)) * 6.28) * 0.025;
        float traceY = band + (source - 0.5) * 0.24 * trace_gain + ripple;
        float d = abs(uv.y - traceY);
        float mask = (1.0 - smoothstep(trace_width, trace_width * 2.4, d)) * active;
        traceAccum = max(traceAccum, mask);
        float3 c = (frac(fi * 0.37 + 0.2) > 0.62) ? accent_color : line_color;
        traceCol += c * mask;
    }
    float sweep = frac(0.5 + t * 0.085);
    float head = 1.0 - smoothstep(0.0, 0.012, abs(uv.x - sweep));
    traceCol += accent_color * head * 0.9;
    float composite = saturate(scope_mix);
    ink = lerp(base.rgb * 0.35 + dark * 0.2, ink + traceCol, composite);
    ink += accent_color * head * 0.35;
    OutputUAV[tid.xy] = float4(saturate(ink), 1.0);
}
