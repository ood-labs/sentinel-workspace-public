// frame_hud viewport-mask output — the circular clip (1 inside the porthole).
float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float m = _Tex0.SampleLevel(PointSampler, In.Uv, 0).a;
    return float4(m, m, m, 1.0);
}
