// post — final finish: chromatic aberration, multi-tap bloom, teal/orange split-tone
// grade, contrast/saturation, vignette, film grain. Consumes the composited Scene.

RWTexture2D<float4> OutputUAV : register(u0);

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

float3 sceneAt(float2 uv)
{
    return _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;

    // chromatic aberration
    float2 dir = uv - 0.5;
    float3 scene;
    scene.r = sceneAt(uv + dir * chroma * 0.012).r;
    scene.g = sceneAt(uv).g;
    scene.b = sceneAt(uv - dir * chroma * 0.012).b;

    // multi-tap bloom (golden-angle gather over thresholded scene)
    float3 bloom = float3(0, 0, 0);
    float wsum = 0.0;
    [loop]
    for (int k = 0; k < 48; k++)
    {
        float fk = (float)k;
        float a = fk * 2.399963;
        float rad = sqrt(fk / 48.0) * bloom_radius;
        float2 off = float2(cos(a), sin(a)) * rad * float2(1.0 / asp, 1.0);
        float3 s = sceneAt(uv + off);
        float l = dot(s, float3(0.299, 0.587, 0.114));
        float t = max(l - bloom_threshold, 0.0);
        float w = exp(-rad * rad * 8.0);
        bloom += s * t * w;
        wsum += w;
    }
    bloom /= max(wsum, 1e-4);

    float3 col = scene + bloom * bloom_intensity;
    col *= exposure;

    // teal/orange split-tone
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col += shadow_tint * (1.0 - smoothstep(0.0, 0.4, lum)) * split_balance;
    col += highlight_tint * smoothstep(0.5, 1.2, lum) * split_balance;

    // contrast + saturation
    col = (col - 0.5) * contrast + 0.5;
    float g = dot(col, float3(0.299, 0.587, 0.114));
    col = lerp(float3(g, g, g), col, saturation);

    // vignette
    float2 q = (uv - 0.5) * float2(asp, 1.0);
    float vig = 1.0 - vignette * saturate(dot(q, q) * 1.8);
    col *= vig;

    // film grain
    float grain = (hash21(uv * _Resolution.xy + frac(_Time) * 97.0) - 0.5) * grain_amt;
    col += grain;

    OutputUAV[pixel] = float4(max(col, 0.0), 1.0);
}
