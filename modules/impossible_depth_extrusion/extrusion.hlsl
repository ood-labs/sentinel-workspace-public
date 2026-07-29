RWTexture2D<float4> OutputUAV : register(u0);

float de_hash(float2 p) { return frac(sin(dot(p, float2(41.7, 17.3))) * 951.17); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float phase = extrusion_phase * 6.2831853 + _Time * relief_speed;
    float4 base = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float2 dir = normalize(float2(cos(phase * 0.37), sin(phase * 0.53))) * px * 22.0;
    float layers = max(2.0, depth_layers);
    float3 volume = 0.0;
    float3 front = 0.0;
    float edge = 0.0;
    [unroll] for (int i = 0; i < 12; i++) {
        float fi = (float)i;
        float active = step(fi + 0.5, layers);
        float z = fi / max(1.0, layers - 1.0) - 0.5;
        float2 warp = dir * z * extrusion * (0.45 + relief);
        warp += float2(sin(uv.y * 18.0 + phase + fi), cos(uv.x * 13.0 - phase * 0.7 + fi)) * px * relief * 5.0 * z;
        float3 s = _Tex0.SampleLevel(LinearSampler, saturate(uv + warp), 0).rgb;
        float lum = dot(s, float3(0.299, 0.587, 0.114));
        volume += s * active * (0.42 + 0.58 * (1.0 - abs(z)));
        front = max(front, s * active);
        edge = max(edge, abs(lum - dot(_Tex0.SampleLevel(LinearSampler, saturate(uv + warp + dir * px * 3.0), 0).rgb, float3(0.299, 0.587, 0.114))) * active);
    }
    volume /= layers;
    float seam = smoothstep(0.003, 0.075, edge) * edge_gain;
    float reliefPulse = 0.62 + 0.38 * sin(phase + uv.x * 8.0 + uv.y * 5.0);
    float3 ink = volume * 0.92 + front * 0.34 + volume_color * seam * reliefPulse * 1.25;
    ink += accent_color * seam * 1.35;
    float3 outCol = lerp(base.rgb * 0.18 + dark_color * 0.28, ink, extrusion_mix);
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
