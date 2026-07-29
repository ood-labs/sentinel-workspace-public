RWTexture2D<float4> OutputUAV : register(u0);

float hc_hash(float2 p) {
    p = frac(p * float2(0.187, 0.277));
    p += dot(p, p.yx + 16.91);
    return frac(p.x * p.y * 30.31);
}

float hc_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float t = halftone_phase * 6.2831853 * pulse_speed;
    float2 grid = float2(grid_x, grid_y);
    float2 cellId = floor(uv * grid);
    float2 cellUv = (cellId + 0.5) / grid;
    cellUv.x += (cellUv.y - 0.5) * cell_shear;
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 sample = _Tex0.SampleLevel(LinearSampler, saturate(cellUv), 0).rgb;
    float lum = dot(sample, float3(0.299, 0.587, 0.114));
    float pulse = 0.5 + 0.5 * sin(t + cellId.x * 0.17 + cellId.y * 0.31);
    float radius = saturate((0.16 + lum * 0.78) * dot_scale * (0.72 + 0.28 * pulse));
    float2 local = frac(uv * grid) - 0.5;
    float2 aspect = float2(grid.y / grid.x, 1.0);
    float d = length(local * aspect);
    float dotMask = 1.0 - smoothstep(radius * 0.48, radius * 0.50 + 0.012, d);
    float cellEdge = hc_line(local.x * 2.0 + 0.5, 0.012) + hc_line(local.y * 2.0 + 0.5, 0.012);
    float scan = hc_line((uv.y + uv.x * 0.16) * 13.0 - t * 0.11, 0.014);
    float head = smoothstep(0.035, 0.0, abs(uv.x - frac(halftone_phase * pulse_speed * 0.63)));

    float3 ink = lerp(dark_color, dot_color, dotMask);
    ink += dot_color * cellEdge * 0.06;
    ink = lerp(ink, accent_color, head * scan_gain + scan * 0.18 * scan_gain);
    float3 col = lerp(base, ink, halftone_mix);
    col += (hc_hash((float2)tid.xy + halftone_phase * 67.0) - 0.5) * 0.010 * halftone_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
