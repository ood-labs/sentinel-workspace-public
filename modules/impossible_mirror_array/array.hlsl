RWTexture2D<float4> OutputUAV : register(u0);

float ma_line(float d, float w) { return 1.0 - smoothstep(w, w * 2.5, abs(d)); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 aspect = float2(_Resolution.x / _Resolution.y, 1.0);
    float2 p = (uv - 0.5) * aspect;
    float r = length(p);
    float a = atan2(p.y, p.x);
    float phase = array_phase * 6.2831853 + _Time * spin_speed;
    float sectors = max(3.0, sector_count);
    float wedge = 6.2831853 / sectors;
    float localA = frac((a + phase) / wedge);
    localA = abs(localA * 2.0 - 1.0);
    float2 q = float2(cos(localA * wedge - phase), sin(localA * wedge - phase)) * r;
    q.x /= aspect.x;
    float2 sampleUv = saturate(q + 0.5);
    float4 src = _Tex0.SampleLevel(LinearSampler, sampleUv, 0);
    float3 col = src.rgb;
    float seam = ma_line(localA - 0.02, 0.012) + ma_line(localA - 0.98, 0.012);
    float ring = ma_line(r - radius, 0.010);
    float core = 1.0 - smoothstep(occlusion, occlusion + 0.025, r);
    float ticks = ma_line(frac((a + phase * 0.4) / wedge) - 0.5, 0.018) * step(radius * 0.7, r);
    float3 ink = lerp(dark_color, col, 0.52);
    ink += metal_color * (seam * seam_gain * 0.55 + ring * 0.7 + ticks * 0.18);
    ink += accent_color * (seam * seam_gain * 0.7 + ring * 0.42);
    ink = lerp(ink, dark_color, core);
    float3 outCol = lerp(col * 0.18 + dark_color * 0.25, ink, array_mix);
    outCol += accent_color * ma_line(r, 0.006) * 0.18;
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
