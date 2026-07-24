RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    // Runtime texture registers follow declared input order:
    // Tex0 lattice enclosure, Tex1 chaos hero, Tex2 grid, Tex3 contour,
    // Tex4 HUD, Tex5 wire cage, Tex6 particles, Tex7 portal depth field, Tex8 shell.
    float3 lattice = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 hero    = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 grid    = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 accent  = _Tex3.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 hud     = _Tex4.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 wire    = _Tex5.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 particles = _Tex6.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 portal = _Tex7.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 shell = _Tex8.SampleLevel(LinearSampler, uv, 0).rgb;

    float2 centered = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0);
    float radial = length(centered);
    // Aperture hierarchy: instrument textures yield through the hero zone and
    // reappear around it, creating a spatial portal instead of a flat overlay stack.
    float edge_mask = smoothstep(hero_aperture - aperture_softness, hero_aperture + aperture_softness, radial);
    float center_mask = 1.0 - edge_mask;

    // Enclosure is a low-frequency spatial bed; the chaos branch owns the focal mass.
    float3 col = lattice * lattice_gain + hero * hero_gain;
    col += grid * grid_gain * lerp(0.34, 1.0, edge_mask);
    col += accent * accent_gain;
    col += hud * hud_gain;
    col += wire * wire_tint * wire_gain * lerp(0.18, 1.0, edge_mask);
    col += particles * particle_gain * lerp(0.42, 1.0, edge_mask);
    col += portal * portal_gain * lerp(0.6, 1.0, edge_mask);
    col += shell * shell_gain * lerp(0.25, 1.0, edge_mask);

    // Preserve black negative space while keeping the hero and instrument edges crisp.
    col = max(col - shadow * (1.0 - saturate(hero * 2.0)), 0.0);
    col = pow(max(col, 0.0), 1.0 / max(contrast, 0.001));
    OutputUAV[pixel] = float4(col * master_mix, 1.0);
}
