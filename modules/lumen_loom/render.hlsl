RWTexture2D<float4> OutputUAV : register(u0);

float3 palette(float t) {
    float3 a = float3(0.035, 0.010, 0.075);
    float3 b = float3(0.020, 0.720, 0.920);
    float3 c = float3(1.000, 0.180, 0.510);
    float3 d = float3(1.000, 0.840, 0.260);
    if (palette_mode == 1) { a=float3(0.005,0.035,0.025); b=float3(0.06,0.95,0.62); c=float3(0.35,0.65,1.0); d=float3(0.95,1.0,0.72); }
    if (palette_mode == 2) { a=float3(0.045,0.012,0.004); b=float3(1.0,0.24,0.03); c=float3(0.62,0.08,1.0); d=float3(1.0,0.92,0.50); }
    float3 col = lerp(a, b, smoothstep(0.0, 0.46, t));
    col = lerp(col, c, smoothstep(0.38, 0.78, t));
    return lerp(col, d, smoothstep(0.76, 1.0, t));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float4 f = _Tex0.Load(int3(id.xy, 0));
    float e = 1.0 - exp(-f.r * (0.65 + bloom * 0.9));
    float pulse = 0.82 + 0.18 * sin(f.g * 6.2831853 + _Time * 0.7);
    float3 col = palette(saturate(e * pulse + f.b * 0.4));
    float vignette = smoothstep(0.95, 0.22, length((uv - 0.5) * float2(_Resolution.x/_Resolution.y, 1.0)));
    col *= 0.42 + 0.78 * vignette;
    col += pow(e, 3.0) * bloom * float3(0.35, 0.16, 0.48);
    col = col / (1.0 + col);
    col = pow(saturate(col), 1.0 / 2.2);
    OutputUAV[id.xy] = float4(col, 1.0);
}
