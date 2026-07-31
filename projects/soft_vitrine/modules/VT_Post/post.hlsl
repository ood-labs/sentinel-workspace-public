// VT_Post / post.hlsl — finishing only. Nothing structural happens here.
//
// Bloom is threshold-lifted from the linear HDR the whole chain has been carrying, so the
// horizon seam and the chrome highlights blow out the way real specular does rather than
// smearing the mid-tones. Then a gentle filmic curve, a saturation/contrast trim, chromatic
// separation at the corners, and grain.
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> Src : register(t0);

#define TAP(UV) Src[clamp(int2((UV) * _Resolution.xy), int2(0, 0), \
                          int2((int)_Resolution.x - 1, (int)_Resolution.y - 1))]

float3 filmic(float3 x)
{
    // Hable-style shoulder: keeps saturated plastics from clipping to white paper
    float3 a = x * (2.51 * x + 0.03);
    float3 b = x * (2.43 * x + 0.59) + 0.14;
    return saturate(a / b);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pix = DTid.xy;
    if (pix.x >= (uint)_Resolution.x || pix.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pix + 0.5) / _Resolution.xy;

    // ---------------------------------------------------------------- chromatic separation
    // Zero at the centre, growing to the corners — a lens property, not a global filter.
    float2 cdir = uv - 0.5;
    float r2 = dot(cdir, cdir);
    float ca = aberration * r2 * 0.030;
    float3 col;
    col.r = TAP(uv + cdir * ca).r;
    col.g = TAP(uv).g;
    col.b = TAP(uv - cdir * ca).b;

    // ---------------------------------------------------------------- bloom
    if (bloom > 0.001)
    {
        float3 acc = float3(0, 0, 0);
        float wsum = 0.0;
        [unroll]
        for (int i = 0; i < 12; i++)
        {
            float ang = 6.2831853 * (float)i / 12.0;
            [unroll]
            for (int k = 1; k <= 3; k++)
            {
                float rad = bloom_size * (float)k / 3.0;
                float w = 1.0 / (float)k;
                float3 s = TAP(uv + float2(cos(ang), sin(ang)) * rad).rgb;
                acc += max(s - bloom_threshold, 0.0) * w;
                wsum += w;
            }
        }
        col += acc / max(wsum, 1e-4) * bloom;
    }

    // ---------------------------------------------------------------- grade
    col *= exposure;
    col = filmic(col * 0.85);

    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);
    col = saturate((col - 0.5) * contrast + 0.5 + lift * 0.06);
    col *= tint.rgb;

    // ---------------------------------------------------------------- vignette + grain
    float vig = 1.0 - vignette * smoothstep(0.18, 0.95, r2 * 2.0);
    col *= vig;

    float g = frac(sin(dot(uv * _Resolution.xy + frac(_Time * 37.0), float2(12.9898, 78.233))) * 43758.5453);
    col += (g - 0.5) * grain * 0.09;

    OutputUAV[pix] = float4(saturate(col), 1.0);
}
