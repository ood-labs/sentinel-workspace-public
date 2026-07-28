// Pure analysis downscale. The Module's fixed output resolution performs the
// resize while the full-resolution plate continues directly to Program.

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float3 color = _Tex0.SampleLevel(LinearSampler, input.Uv, 0.0).rgb;
    return float4(color, 1.0);
}
