// resample — resolution converter. Samples input:0 and emits it at THIS module's own
// resolution (resolution_width/height), so a high-res source (e.g. StreamDiff's 2x output)
// is brought down to a sane working size before matte/depth/tracking/atlas consume it.
// ps_5_0 fullscreen; injected VS_OUTPUT{Position,Uv}, _Tex0, LinearSampler.

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float3 c = _Tex0.SampleLevel(LinearSampler, input.Uv, 0).rgb;
    // gentle post-downscale sharpen to counter bilinear softness
    float2 px;
    _Tex0.GetDimensions(px.x, px.y);
    float2 t = 1.0 / max(px, 1.0);
    float3 blur = (
        _Tex0.SampleLevel(LinearSampler, input.Uv + float2( t.x, 0), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, input.Uv + float2(-t.x, 0), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, input.Uv + float2(0,  t.y), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, input.Uv + float2(0, -t.y), 0).rgb) * 0.25;
    c = c + (c - blur) * sharpen;
    return float4(saturate(c), 1.0);
}
