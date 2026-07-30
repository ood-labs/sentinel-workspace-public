float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float depthValue = _Tex0.SampleLevel(PointSampler, In.Uv, 0).a;
    return float4(depthValue, depthValue, depthValue, 1.0);
}
