RWTexture2D<float4> OutputUAV : register(u0);

float rp_hash(float2 p) {
    p = frac(p * float2(0.149, 0.287));
    p += dot(p, p.yx + 13.73);
    return frac(p.x * p.y * 31.19);
}

float rp_rect(float2 p, float2 halfSize) {
    float2 q = abs(p) - halfSize;
    return smoothstep(0.012, -0.012, max(q.x, q.y));
}

float rp_border(float2 p, float2 halfSize, float width) {
    float outer = rp_rect(p, halfSize);
    float inner = rp_rect(p, max(halfSize - width, 0.001));
    return saturate(outer - inner);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 center = float2(pocket_center_x, pocket_center_y);
    float2 p = uv - center;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    p.x *= aspect;
    float2 halfSize = float2(pocket_size * aspect * 0.52, pocket_size * 0.50);
    float inside = rp_rect(p, halfSize);
    float t = pocket_phase * 6.2831853 * pocket_rate;

    float2 q = uv;
    float3 recursive = 0.0;
    float weight = 0.0;
    [unroll]
    for (int i = 0; i < 5; ++i) {
        float fi = (float)i;
        float a = t * (0.42 + fi * 0.11) + fi * 1.19;
        float2 local = q - center;
        float2 rot = float2(cos(a) * local.x - sin(a) * local.y,
                            sin(a) * local.x + cos(a) * local.y);
        float zoom = 1.0 + recursion_zoom * (fi + 1.0) * 0.72;
        q = saturate(center + rot * zoom + float2(cos(t + fi) * orbit_amount,
                                                   sin(t * 0.8 + fi * 0.7) * orbit_amount));
        float w = 1.0 / (fi + 1.0);
        recursive += _Tex0.SampleLevel(LinearSampler, q, 0).rgb * w;
        weight += w;
    }
    recursive /= max(weight, 0.001);
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float breathing = 0.80 + 0.20 * sin(t * 1.4 + p.y * 4.0);
    float pocket = inside * pocket_mix * breathing;
    float3 pocketSurface = recursive * 0.72 + pocket_color * 0.28;
    float3 col = lerp(base, pocketSurface, pocket);

    float border = rp_border(p, halfSize, 0.010);
    float inset = rp_border(p * 0.86 + float2(sin(t) * 0.01, cos(t) * 0.008), halfSize * 0.84, 0.006);
    float nested = 0.0;
    [unroll]
    for (int j = 1; j < 4; ++j) {
        float fj = (float)j;
        float2 np = p * (1.0 + fj * 0.12) + float2(sin(t * 0.7 + fj) * 0.012, cos(t * 0.6 + fj) * 0.010);
        nested += rp_border(np, halfSize * (0.72 - fj * 0.13), 0.004 + fj * 0.001);
    }
    float scan = smoothstep(0.012, 0.0, abs(frac((p.y + t * 0.025) * 15.0) - 0.5));
    float ink = saturate((border + inset * 0.56 + nested * 0.44 + scan * 0.16) * frame_gain * pocket_mix);
    col = lerp(col, frame_color, ink);
    float corner = smoothstep(0.020, 0.0, abs(abs(p.x) - halfSize.x)) * smoothstep(0.06, 0.0, abs(abs(p.y) - halfSize.y));
    col = lerp(col, pocket_color, corner * pocket_mix * 0.42);
    col += (rp_hash((float2)tid.xy + pocket_phase * 17.0) - 0.5) * 0.006 * pocket_mix * inside;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
