float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float3 color = _Tex0.SampleLevel(PointSampler, In.Uv, 0).rgb;
    return float4(color, 1.0);
}
