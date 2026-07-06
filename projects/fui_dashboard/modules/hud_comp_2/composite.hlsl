// hud_comp — FUI compositor. bg is the opaque base; every other layer is an
// additive glow contribution with its own gain.
// Inputs: 0 BG, 1 Orbits, 2 Panels, 3 Leaders, 4 Gauge, 5 Labels.

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float3 bg      = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 orbits  = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 panels  = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 leaders = _Tex3.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 gauge   = _Tex4.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 labels  = _Tex5.SampleLevel(LinearSampler, uv, 0).rgb;

    float3 col = bg * bg_gain;
    col += orbits  * orbits_gain;
    col += panels  * panels_gain;
    col += leaders * leaders_gain;
    col += gauge   * gauge_gain;
    col += labels  * labels_gain;

    col *= master_mix;
    OutputUAV[pixel] = float4(col, 1.0);
}
