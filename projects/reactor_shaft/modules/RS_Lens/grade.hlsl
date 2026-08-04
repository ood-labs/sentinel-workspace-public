// RS_Lens / grade.hlsl — the finish.
//
// Composites the two bloom scales and the flare over the beauty, then does the things that make
// this a photograph of a shaft rather than a render of one: radial chromatic aberration, an
// exposure and a filmic roll-off, a split grade that puts teal in the shadows and keeps the
// magenta in the highlights, a vignette, and grain.
//
// The renderer hands over RGBA16F with LINEAR DEPTH IN ALPHA, so the haze grade below can be
// depth-aware instead of guessing depth from luminance.
Texture2D<float4> Beauty : register(t0);
Texture2D<float4> BloomTight : register(t1);
Texture2D<float4> BloomWide : register(t2);
Texture2D<float4> Streak : register(t3);
RWTexture2D<float4> OutputUAV : register(u0);

// ACES filmic approximation. Applied on the MAX channel rather than per channel further down,
// because a per-channel curve desaturates every emitter toward white and the reference's tubes
// stay saturated right up to their blown cores.
float3 aces(float3 x)
{
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

float3 sampleAberrated(uint2 px, uint2 dim, float2 uv, float amt)
{
    if (amt <= 0.0001) return Beauty[px].rgb;
    // radial: zero in the centre, growing to the corners, which is how a real lens behaves
    float2 c = uv - 0.5;
    float2 off = c * amt;
    int2 pr = clamp((int2)((uv + off * 1.00) * (float2)dim), int2(0, 0), (int2)dim - 1);
    int2 pg = clamp((int2)((uv + off * 0.50) * (float2)dim), int2(0, 0), (int2)dim - 1);
    int2 pb = clamp((int2)((uv - off * 0.60) * (float2)dim), int2(0, 0), (int2)dim - 1);
    return float3(Beauty[(uint2)pr].r, Beauty[(uint2)pg].g, Beauty[(uint2)pb].b);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (px.x >= W || px.y >= H) return;
    uint2 dim = uint2(W, H);
    float2 uv = ((float2)px + 0.5) / float2(W, H);

    float depth = Beauty[px].a;
    float3 col = sampleAberrated(px, dim, uv, aberration * 0.012);

    // --- glare
    float3 bt = BloomTight[px].rgb;
    float3 bw = BloomWide[px].rgb;
    col += (bt * bloom_tight + bw * bloom_wide_gain) * bloom_gain;
    col += Streak[px].rgb * flare_gain;

    // --- exposure and roll-off
    col *= exposure;
    // Roll off on the max channel and rescale, so a blown magenta tube blows toward WHITE-hot
    // magenta rather than sliding to neutral grey the way a per-channel curve drags it.
    float mx = max(col.r, max(col.g, col.b));
    float rolled = aces(mx.xxx).x;
    col = (mx > 1e-5) ? col * (rolled / mx) : col;
    col = lerp(aces(col), col, tone_sat);

    // --- split grade. Teal into the shadows, the magenta chord left alone up top: the
    // reference's blacks are not neutral, they are cold, and that single fact does more for the
    // read than any amount of saturation.
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    float shadow = 1.0 - smoothstep(0.0, 0.42, lum);
    float high = smoothstep(0.45, 1.0, lum);
    col += shadow_tint * shadow * shadow_amt;
    col += high_tint * high * high_amt;

    // depth-graded cool, so the near foreground stays cold and heavy
    float d01 = saturate(depth / max(depth_ref, 1.0));
    col *= lerp(float3(1.0, 1.0, 1.0), depth_tint * 2.0, (1.0 - d01) * depth_amt);

    // --- saturation and contrast
    lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(lum.xxx, col, saturation);
    col = saturate((col - 0.5) * contrast + 0.5 + lift);

    // --- vignette
    float2 vc = (uv - 0.5) * float2((float)W / max((float)H, 1.0), 1.0);
    float vig = 1.0 - smoothstep(vignette_start, vignette_start + 0.75, length(vc) * 1.35);
    col *= lerp(1.0, vig, vignette);

    // --- grain. Scaled by _DeltaTime-independent time so it moves at a filmic rate rather than
    // at whatever the cook rate happens to be.
    float2 gseed = (float2)px + floor(_Time * 24.0) * 71.7;
    float g = frac(sin(dot(gseed, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    col += g * grain * lerp(0.35, 1.0, 1.0 - saturate(lum));

    OutputUAV[px] = float4(saturate(col), 1.0);
}
