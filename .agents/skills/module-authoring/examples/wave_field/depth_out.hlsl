// Extract depth from march pass alpha channel (1 = near, 0 = far)

float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float d = _Tex0.SampleLevel(PointSampler, In.Uv, 0).a;
    return float4(d, d, d, 1.0);
}
