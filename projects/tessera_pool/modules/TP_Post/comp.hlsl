// TP_Post / comp.hlsl — composite, grade, and edge antialias.
//
// The renderer's geometry is analytic — box faces and a bracketed height field — so its edges
// are hard by construction and there is no partial coverage anywhere. That makes a gradient
// edge filter exactly the right tool here: the only aliasing present is on silhouettes, and it
// is worth removing without paying for a second ray per pixel.
//
// THE GRADE DOES NOT TONEMAP THE BACKDROP. The studio is an art-directed flat gradient that is
// already exactly the value it should be; pushing it through a filmic curve desaturates and
// lifts it for no reason. Only the range ABOVE the backdrop — the rim, the glints, the caustic
// cusps — gets rolled off, and it is rolled off on the MAXIMUM channel rather than per channel,
// because a per-channel curve on a saturated teal pulls it toward white as it brightens and
// chalks out exactly the colour the tank is made of.
RWTexture2D<float4> OutputUAV : register(u0);

float3 rollMax(float3 c, float knee)
{
    float m = max(max(c.r, c.g), c.b);
    if (m <= knee) return c;
    float rolled = knee + (m - knee) / (1.0 + (m - knee) / max(1.0 - knee, 1e-3));
    return c * (rolled / max(m, 1e-4));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 res = _Resolution.xy;
    float2 uv = ((float2)tid.xy + 0.5) / res;
    float2 px = 1.0 / res;

    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    // ---- edge antialias, gradient-directed
    if (aa_amount > 0.001)
    {
        float3 lw = float3(0.2126, 0.7152, 0.0722);
        float lC = dot(c, lw);
        float lL = dot(_Tex0.SampleLevel(LinearSampler, uv - float2(px.x, 0), 0).rgb, lw);
        float lR = dot(_Tex0.SampleLevel(LinearSampler, uv + float2(px.x, 0), 0).rgb, lw);
        float lD = dot(_Tex0.SampleLevel(LinearSampler, uv - float2(0, px.y), 0).rgb, lw);
        float lU = dot(_Tex0.SampleLevel(LinearSampler, uv + float2(0, px.y), 0).rgb, lw);

        float2 g = float2(lR - lL, lU - lD);
        float mag = length(g);
        if (mag > aa_threshold)
        {
            // Reconstruct ALONG the edge, never across it. The old resolve averaged four
            // neighbours and discarded the center sample completely, which made a stable edge
            // unnecessarily soft. Keep most of the center energy and use the neighbours only
            // to suppress staircase phase changes on diagonals.
            float2 dir = normalize(float2(-g.y, g.x)) * px * aa_amount;
            float3 nearPair = (_Tex0.SampleLevel(LinearSampler, uv + dir, 0).rgb
                             + _Tex0.SampleLevel(LinearSampler, uv - dir, 0).rgb) * 0.5;
            float3 farPair = (_Tex0.SampleLevel(LinearSampler, uv + dir * 2.0, 0).rgb
                            + _Tex0.SampleLevel(LinearSampler, uv - dir * 2.0, 0).rgb) * 0.5;
            float3 neighbourhood = lerp(nearPair, farPair, 0.22);
            float centerWeight = lerp(0.30, 0.86, saturate(aa_crispness));
            float3 resolved = lerp(neighbourhood, c, centerWeight);

            float lMin = min(lC, min(min(lL, lR), min(lD, lU)));
            float lMax = max(lC, max(max(lL, lR), max(lD, lU)));
            float edgeWeight = saturate((lMax - lMin - aa_threshold)
                                     / max(aa_threshold * 3.0, 0.02));
            c = lerp(c, resolved, edgeWeight);
        }
    }

    // ---- bloom
    float3 b = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    c += b * bloom;

    // ---- grade
    c *= exposure;
    float l = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = lerp(l.xxx, c, saturation);
    c = (c - 0.5) * contrast + 0.5 + lift;
    c = max(c, 0.0);

    // split tone, gentle: the reference's shadows sit cool and its highlights sit almost neutral
    float t = saturate(l * 1.6);
    c *= lerp(shadow_tint, highlight_tint, t);

    c = rollMax(c, roll_knee);

    // ---- lens
    float2 q = (uv - 0.5) * float2(res.x / max(res.y, 1.0), 1.0);
    c *= 1.0 - saturate(dot(q, q)) * vignette;

    OutputUAV[tid.xy] = float4(max(c, 0.0), 1.0);
}
