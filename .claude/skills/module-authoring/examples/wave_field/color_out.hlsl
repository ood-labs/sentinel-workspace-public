// Extract color from march pass, set alpha = 1.0 for display

float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float3 col = _Tex0.SampleLevel(PointSampler, In.Uv, 0).rgb;
    return float4(col, 1.0);
}
