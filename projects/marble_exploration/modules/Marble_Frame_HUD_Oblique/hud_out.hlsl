// frame_hud HUD color output — alpha = luminance for additive compositing.
float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float4 c = _Tex0.SampleLevel(PointSampler, In.Uv, 0);
    float a = saturate(max(c.r, max(c.g, c.b)));
    return float4(c.rgb, a);
}
