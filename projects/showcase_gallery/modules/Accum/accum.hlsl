// accum — persistent feedback canvas. Composites the incoming stamp layer (input:0, straight
// alpha) OVER its own previous output (input:1, wired back to this node's Out). decay=1 keeps
// every imprint forever; decay<1 slowly fades old ones into trails. This is what makes cut-out
// eye/mouth stamps "stick on top and pile up forever". ps_5_0; _Tex0 = new, _Tex1 = feedback.

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float4 prev = _Tex1.SampleLevel(LinearSampler, uv, 0);
    float4 nw   = _Tex0.SampleLevel(LinearSampler, uv, 0);

    prev.rgb *= decay;
    prev.a   *= decay;

    float a = saturate(nw.a * paint);
    float3 col = prev.rgb * (1.0 - a) + nw.rgb * a;
    float outA = saturate(max(prev.a, a));
    return float4(col, outA);
}
