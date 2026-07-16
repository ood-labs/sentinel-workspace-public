float hashPost(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float bandId = floor(uv.y * 42.0);
    float bandGate = step(0.965, hashPost(float2(bandId, floor(_Time * 5.0))));
    float bandShift = (hashPost(float2(bandId, 91.7)) - 0.5) * glitch * bandGate;
    float2 shifted = saturate(uv + float2(bandShift, 0.0));

    float chromaPx = (0.35 + chroma * 1.65) / max(_Resolution.x, 1.0);
    float3 col;
    col.r = _Tex0.SampleLevel(LinearSampler, saturate(shifted + float2(chromaPx, 0.0)), 0).r;
    col.g = _Tex0.SampleLevel(LinearSampler, shifted, 0).g;
    col.b = _Tex0.SampleLevel(LinearSampler, saturate(shifted - float2(chromaPx, 0.0)), 0).b;

    col = (col - 0.5) * contrast + 0.5 + lift;
    col += float3(temperature * 0.045, temperature * 0.008, -temperature * 0.040);
    float noise = hashPost((floor(uv * _Resolution.xy) + floor(_Time * 47.0)) * 0.713) - 0.5;
    col += noise * grain;
    float2 p = (uv - 0.5) * float2(_Resolution.x / max(_Resolution.y, 1.0), 1.0);
    col *= 1.0 - vignette * smoothstep(0.18, 0.72, dot(p, p));
    return float4(saturate(col), 1.0);
}
