RWTexture2D<float4> OutputUAV : register(u0);

struct MarbleProfile {
    float4 stone_color_roughness;
    float4 vein_color_scale;
    float4 vein_contrast_pore_scale;
    float4 cavity_subsurface_micro_normal;
};
StructuredBuffer<MarbleProfile> Profile : register(t0);

float marbleVein(float2 p, float scale, float contrast) {
    float broad = sin(p.x * scale + sin(p.y * 2.7) * 2.2);
    float fine = sin(p.x * scale * 2.8 - p.y * 7.0 + sin(p.y * 4.0));
    float bands = abs(broad * 0.72 + fine * 0.28);
    return pow(saturate(1.0 - bands), max(0.4, contrast));
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 p = (uv - 0.5) * float2(2.0, 1.2);
    MarbleProfile m = Profile[0];
    float vein = marbleVein(p, m.vein_color_scale.w, m.vein_contrast_pore_scale.x);
    float pore = sin(p.x * 80.0 + sin(p.y * 31.0)) * sin(p.y * 67.0);
    float grain = 1.0 + pore * m.vein_contrast_pore_scale.y * 0.035;
    float3 base = m.stone_color_roughness.rgb * grain;
    float3 col = lerp(base, m.vein_color_scale.rgb, vein * 0.72);
    float edge = smoothstep(0.48, 0.40, abs(p.x));
    col *= 0.58 + edge * 0.42;
    col += m.vein_color_scale.rgb * smoothstep(0.92, 1.0, vein) * 0.22;
    OutputUAV[px] = float4(saturate(col), 1.0);
}
