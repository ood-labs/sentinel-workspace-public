RWTexture2D<float4> OutputUAV : register(u0);

float ms_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

float ms_rect(float2 p, float2 halfSize) {
    float2 q = abs(p) - halfSize;
    return smoothstep(0.012, -0.012, max(q.x, q.y));
}

float ms_border(float2 p, float2 halfSize, float width) {
    return saturate(ms_rect(p, halfSize) - ms_rect(p, max(halfSize - width, 0.001)));
}

float ms_hash(float2 p) {
    p = frac(p * float2(0.179, 0.229));
    p += dot(p, p.yx + 14.31);
    return frac(p.x * p.y * 23.71);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 p = uv - 0.5;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    p.x *= aspect;
    float t = slab_phase * 6.2831853 * slab_rate;
    float bob = sin(t * 0.8) * 0.035;
    float2 c = float2(slab_center_x - 0.5, slab_center_y - 0.5);
    c.x *= aspect;
    c.y += bob;

    float2 local = p - c;
    local.x += slab_tilt * local.y;
    float2 halfSize = float2(slab_width * aspect * 0.5, slab_height * 0.5);
    float slab = ms_rect(local, halfSize);

    float2 backC = c + float2(-0.16 * aspect, -0.12);
    float2 backLocal = p - backC;
    backLocal.x += (slab_tilt * 0.7) * backLocal.y;
    float2 backHalf = halfSize * float2(0.70, 0.70);
    float backSlab = ms_rect(backLocal, backHalf);

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float2 insetUv = saturate(float2(slab_center_x, slab_center_y) + (uv - float2(slab_center_x, slab_center_y)) * 1.42);
    insetUv += float2(sin(t + uv.y * 5.0) * 0.014, cos(t * 0.7 + uv.x * 4.0) * 0.010);
    float3 inset = _Tex0.SampleLevel(LinearSampler, insetUv, 0).rgb;

    float3 col = lerp(base, slab_color * 0.58 + inset * 0.44, slab * slab_mix);
    col = lerp(col, inset * 0.70 + slab_color * 0.24, backSlab * slab_mix * 0.62);

    float frontEdge = ms_border(local, halfSize, 0.012);
    float backEdge = ms_border(backLocal, backHalf, 0.008);
    float registration = ms_line((local.y + t * 0.04) * 19.0, 0.014) * slab;
    float cut = ms_line((local.x - local.y * 0.44) * 8.0 - t * 0.08, 0.018) * slab;
    float ink = saturate((frontEdge * 0.92 + backEdge * 0.50 + registration * 0.18 + cut * 0.20) * edge_gain * slab_mix);
    col = lerp(col, edge_color, ink);

    float notch = ms_rect(local - float2(halfSize.x * 0.58, -halfSize.y * 0.72), float2(0.032, 0.010));
    col = lerp(col, edge_color, notch * slab_mix * 0.74);
    col += (ms_hash((float2)tid.xy + slab_phase * 47.0) - 0.5) * 0.007 * slab_mix * max(slab, backSlab);
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
