// grid_warp — faint mesh grid whose UVs are DISPLACED by the shared Field
// (slope + elevation), plus a mild perspective bulge. Reads Field (input:0).

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    // perspective bulge around center
    float2 cen = uv - 0.5;
    float2 g_uv = 0.5 + cen * (1.0 + perspective * dot(cen, cen));

    // field-driven displacement — warp along the gradient of a SMOOTHED field so
    // grid lines bend continuously (a coherent net) instead of shredding.
    float2 texel = 1.0 / _Resolution.xy;
    float o = 20.0;
    float hl = _Tex0.SampleLevel(LinearSampler, uv - float2(o * texel.x, 0), 0).r;
    float hr = _Tex0.SampleLevel(LinearSampler, uv + float2(o * texel.x, 0), 0).r;
    float hd = _Tex0.SampleLevel(LinearSampler, uv - float2(0, o * texel.y), 0).r;
    float hu = _Tex0.SampleLevel(LinearSampler, uv + float2(0, o * texel.y), 0).r;
    float2 grad = float2(hr - hl, hu - hd);
    g_uv += grad * warp_amount * 0.15;
    g_uv += _Time * drift_speed;

    // grid lines
    float2 gr = abs(frac(g_uv * grid_density) - 0.5);
    float lx = 1.0 - smoothstep(0.0, line_width, gr.x);
    float ly = 1.0 - smoothstep(0.0, line_width, gr.y);
    float grid = max(lx, ly);

    // fades: dim near very center, dim toward the far edges
    float r = length(cen) * 2.0;
    float fc = smoothstep(0.0, fade_center, r);
    float fe = 1.0 - smoothstep(fade_edges, fade_edges + 0.5, r);
    float amt = grid * fc * fe * intensity;

    float3 col = grid_color * amt;
    OutputUAV[pixel] = float4(col, saturate(amt));
}
