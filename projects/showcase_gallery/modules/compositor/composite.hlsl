// compositor — ordered additive blend of every scene layer with per-layer gain and
// an optional viewport-mask clip that keeps the terrain inside the porthole.
// Inputs: 0 Atmosphere, 1 Grid, 2 Blue, 3 Accent, 4 Links, 5 Nodes, 6 HUD,
//         7 Labels, 8 Viewport Mask.

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float3 atmos = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 grid  = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 blue  = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 acc   = _Tex3.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 links = _Tex4.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 nodes = _Tex5.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 hud   = _Tex6.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 lab   = _Tex7.SampleLevel(LinearSampler, uv, 0).rgb;
    float  vmask = _Tex8.SampleLevel(LinearSampler, uv, 0).r;

    // soft clip for terrain layers (keep inside porthole)
    float clip = (viewport_clip != 0) ? lerp(1.0, vmask, clip_amount) : 1.0;

    float3 col = atmos * bg_gain + bg_tint * 0.0;
    col += grid  * grid_gain   * clip;
    col += blue  * blue_gain   * clip;
    col += acc   * accent_gain * clip;
    col += links * links_gain  * lerp(1.0, vmask, clip_amount * 0.5);
    col += nodes * nodes_gain;
    col += lab   * labels_gain;
    col += hud   * hud_gain;

    col *= master_mix;
    OutputUAV[pixel] = float4(col, 1.0);
}
