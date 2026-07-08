// collage_render present — composite the matte-cut element stamps (pass:stamps, _Tex0) over the
// tracked face background (input:1, _Tex1). Injected VS_OUTPUT{Position,Uv}.

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float3 face = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float4 st = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float3 col = lerp(face, st.rgb, saturate(st.a));
    return float4(col, 1.0);
}
