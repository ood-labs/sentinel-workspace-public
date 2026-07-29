RWTexture2D<float4> OutputUAV : register(u0);

float ct_line(float d, float w) { return 1.0 - smoothstep(w, w * 2.5, abs(d)); }
float ct_grid(float x, float cells, float width) { return ct_line(frac(x * cells) - 0.5, width); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float4 src = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float srcLum = dot(src.rgb, float3(0.299, 0.587, 0.114));
    float phase = tunnel_phase * 6.2831853 + _Time * travel_speed;
    float h = horizon;
    float below = step(h, uv.y);
    float depth = saturate((uv.y - h) / max(0.001, 1.0 - h));
    float z = pow(max(depth, 0.002), perspective);
    float2 floorP = (uv - float2(0.5, h)) / max(z, 0.018);
    floorP.x += sin(phase * 0.35) * 0.06;
    float rail = ct_line(abs(uv.x - 0.5) - z * 0.33, px.x * (2.0 + 4.0 * z)) * rail_gain;
    float cross = ct_grid(floorP.y + phase * 0.08, 10.0, 0.018) * 0.42;
    float lane = ct_grid(floorP.x, 6.0, 0.014) * 0.55;
    float spine = ct_line(floorP.x, 0.008 + z * 0.012) * 0.72;
    float grid = (cross + lane + spine) * below;
    float sig = 0.0;
    [unroll] for (int i = 0; i < 5; i++) {
        float fi = (float)i;
        float laneX = (fi - 2.0) * 0.29;
        float wave = sin(floorP.y * (2.6 + fi * 0.42) + phase * (0.7 + fi * 0.12) + floorP.x * 0.35) * 0.06;
        float source = dot(_Tex0.SampleLevel(LinearSampler, float2(frac(0.5 + floorP.y * 0.055 + fi * 0.11), saturate(0.18 + fi * 0.11)), 0).rgb, float3(0.299, 0.587, 0.114));
        float trace = abs(floorP.x - laneX - (source - 0.5) * 0.22 * signal_gain - wave);
        sig = max(sig, ct_line(trace, 0.012 + z * 0.018) * below);
    }
    float aperture = ct_line(uv.y - h, px.y * 3.0) * 0.9;
    float sweepX = frac(0.5 + phase * 0.045);
    float sweep = (1.0 - smoothstep(0.0, 0.012, abs(uv.x - sweepX))) * 0.65;
    float3 ink = dark_color + metal_color * grid + metal_color * rail + metal_color * sig * 0.35;
    ink += accent_color * (sig * 0.65 + aperture * 0.22 + sweep);
    float3 outCol = lerp(src.rgb * 0.22 + dark_color * 0.3, ink, tunnel_mix);
    outCol += accent_color * ct_line(uv.x - 0.5, px.x * 1.4) * 0.2;
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
