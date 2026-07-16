float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float4 scene = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float vignette = smoothstep(1.05, 0.2, length(uv - 0.5));
    float3 bg = float3(0.015, 0.018, 0.026) + vignette * float3(0.02, 0.024, 0.034);
    float a = saturate(scene.a);
    float3 color = lerp(bg, saturate(scene.rgb * 1.18), a);
    return float4(color, 1.0);
}
