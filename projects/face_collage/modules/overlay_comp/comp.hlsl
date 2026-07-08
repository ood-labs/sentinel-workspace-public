// overlay_comp — stacks three layers: the accumulation (input:0), the CURRENT face-cutout
// composited crisply on top (input:1, straight alpha — so the freshest stamps + their frame-locked
// borders sit on the smeared history), then the vector overlay (input:2, premultiplied) on top.
// _Tex0 = accum, _Tex1 = fresh cutout, _Tex2 = overlay.

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float4 base  = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float4 fresh = _Tex1.SampleLevel(LinearSampler, uv, 0);   // straight alpha
    float4 ov    = _Tex2.SampleLevel(LinearSampler, uv, 0);   // premultiplied

    float fa = saturate(fresh.a * fresh_amt);
    float3 col = base.rgb;
    col = lerp(col, fresh.rgb, fa);                             // fresh cutout over accum
    col = col * (1.0 - ov.a) + ov.rgb;                          // vector overlay over

    // preserve coverage so downstream (finish) keeps the alpha and gaps show the grid
    float a = base.a;
    a = fa + a * (1.0 - fa);
    a = ov.a + a * (1.0 - ov.a);
    return float4(col, saturate(a));
}
