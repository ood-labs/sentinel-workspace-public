// VC_Post / grade.hlsl — lens glare, exposure, tonemap and grade.
//
// TONEMAPPING IS DONE ON THE MAX CHANNEL, not per channel. Running a filmic curve
// independently on r, g and b compresses the bright channel of a saturated colour harder than
// the dim ones, which desaturates exactly the pixels that carry the image's only colour — the
// amber glass and the dispersion fringes chalk out to pale pink and grey. Curving the single
// largest channel and scaling the triple by the same ratio compresses luminance while leaving
// every hue and saturation ratio intact.
RWTexture2D<float4> OutputUAV : register(u0);

float tonemapScalar(float x)
{
    // Filmic shoulder with a controllable white point. Linear near black so the backdrop is
    // not lifted into milk, shoulder above.
    float w = max(white_point, 1.01);
    float a = x * (1.0 + x / (w * w)) / (1.0 + x);
    return a;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;

    float2 res = float2(W, H);
    float2 uv = ((float2)pix + 0.5) / res;
    float2 c2 = uv - 0.5;

    // Lateral chromatic aberration: a real lens spreads the channels radially, strongest at
    // the corners. Tiny — this is a long lens on a product shot, not an anamorphic.
    float3 col;
    if (aberration > 1e-4)
    {
        float2 d = c2 * aberration * 0.006;
        col.r = _Tex0.SampleLevel(LinearSampler, uv + d, 0).r;
        col.g = _Tex0.SampleLevel(LinearSampler, uv, 0).g;
        col.b = _Tex0.SampleLevel(LinearSampler, uv - d, 0).b;
    }
    else
    {
        col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    }

    col += _Tex1.SampleLevel(LinearSampler, uv, 0).rgb * bloom_gain;

    col *= exposure;

    // Vignette, applied BEFORE the tonemap so it darkens scene light rather than painting grey
    // over an already-graded image.
    float r = length(c2 * float2(res.x / res.y, 1.0));
    col *= lerp(1.0, saturate(1.0 - vignette * r * r), 1.0);

    float m = max(col.r, max(col.g, col.b));
    if (m > 1e-6) col *= tonemapScalar(m) / m;

    // grade: lift/gamma/gain on a neutral axis, then a global saturation trim
    col = max(col + black_lift, 0.0);
    col = pow(col, 1.0 / max(gamma_adj, 0.05));
    col *= tint;
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);

    // Fine grain, scaled so it lands in the mid-tones where film grain actually lives rather
    // than crawling all over the black backdrop.
    if (grain > 1e-4)
    {
        float n = frac(sin(dot(uv * res + grain_seed, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
        float g = 1.0 - abs(dot(col, float3(0.333, 0.333, 0.333)) * 2.0 - 1.0);
        col += n * grain * 0.06 * saturate(g);
    }

    OutputUAV[pix] = float4(max(col, 0.0), 1.0);
}
