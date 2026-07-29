RWTexture2D<float4> OutputUAV : register(u0);

float ca_luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }
float ca_line(float d, float w) { return 1.0 - smoothstep(w, w * 2.5, abs(d)); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float phase = atlas_phase * 6.2831853 + _Time * contour_speed;
    float3 src = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float l = ca_luma(src);
    float lx = ca_luma(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(px.x * 2.0, 0.0)), 0).rgb);
    float ly = ca_luma(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0.0, px.y * 2.0)), 0).rgb);
    float edge = length(float2(lx - l, ly - l));
    float levels = max(3.0, contour_levels);
    float contour = ca_line(frac(l * levels + phase * 0.12) - 0.5, contour_width) * 0.92;
    float hatchA = ca_line(frac((uv.x + uv.y * 0.37) * hatch_scale + phase * 0.04) - 0.5, 0.018);
    float hatchB = ca_line(frac((uv.x - uv.y * 0.29) * hatch_scale * 0.73 - phase * 0.03) - 0.5, 0.014);
    float edgeInk = smoothstep(0.008, 0.12, edge) * edge_gain;
    float3 ink = dark_color + contour_color * (contour + hatchA * 0.10 + hatchB * 0.08);
    ink += accent_color * (edgeInk * 1.3 + contour * step(0.72, frac(uv.x * 5.0 + uv.y * 3.0)) * 0.32);
    float3 outCol = lerp(src * 0.12 + dark_color * 0.32, ink, atlas_mix);
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
