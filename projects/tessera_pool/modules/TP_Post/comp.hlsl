// TP_Post / comp.hlsl — composite, antialias, grade, lens.
//
// THE GRADE DOES NOT TONEMAP THE BACKDROP. The studio is an art-directed gradient that is
// already exactly the value it should be; pushing it through a filmic curve desaturates and
// lifts it for no reason. Only the range ABOVE the backdrop — the rim, the glints, the caustic
// cusps — gets rolled off, and it is rolled off on the MAXIMUM channel rather than per channel,
// because a per-channel curve on a saturated teal pulls it toward white as it brightens and
// chalks out exactly the colour the tank is made of.
RWTexture2D<float4> OutputUAV : register(u0);

static float2 gPx;

float3 tpFetch(float2 uv) { return _Tex0.SampleLevel(LinearSampler, uv, 0).rgb; }
float  tpLuma(float2 uv)  { return dot(tpFetch(uv), float3(0.2126, 0.7152, 0.0722)); }

float3 rollMax(float3 c, float knee)
{
    float m = max(max(c.r, c.g), c.b);
    if (m <= knee) return c;
    float rolled = knee + (m - knee) / (1.0 + (m - knee) / max(1.0 - knee, 1e-3));
    return c * (rolled / max(m, 1e-4));
}

// ---------------------------------------------------------------------------
// FXAA.
//
// The gradient filter this replaces reconstructed ALONG the local luma gradient, which is a
// reasonable guess and nothing more: it has no idea how long the edge it is standing on
// actually is, so it applies the same blur to a one-pixel speck as to a fifty-pixel silhouette.
// On the long near-horizontal edges this composition is full of — the waterline, the lip, the
// tile courses in perspective — that under-corrects the staircase while still softening detail
// that was never aliased.
//
// FXAA answers the question properly. It finds the edge's ORIENTATION from the second
// derivative of luma, then SEARCHES along the edge in both directions for where it ends, and
// derives the sub-pixel sample offset from how far along that span this pixel sits. A long edge
// therefore gets a correctly ramped offset from end to end, which is what actually removes a
// staircase rather than blurring it.
//
// Returns the UV to sample the final colour from — an OFFSET, not a colour. That matters for
// the aberration below: shifting the sample point once and then fetching the three channels
// around it keeps the fringing on an antialiased image, whereas fetching three unfiltered
// channels and antialiasing afterwards would put the staircase straight back into red and blue.
// ---------------------------------------------------------------------------
float2 tpFXAA(float2 uv, int steps)
{
    float lC = tpLuma(uv);
    float lN = tpLuma(uv + float2(0.0,  gPx.y));
    float lS = tpLuma(uv + float2(0.0, -gPx.y));
    float lE = tpLuma(uv + float2( gPx.x, 0.0));
    float lW = tpLuma(uv + float2(-gPx.x, 0.0));

    float lMin = min(lC, min(min(lN, lS), min(lE, lW)));
    float lMax = max(lC, max(max(lN, lS), max(lE, lW)));
    float range = lMax - lMin;

    // Early out on flat neighbourhoods. The relative term is what stops the filter chewing on
    // noise in the dark backdrop, where an absolute threshold alone would fire constantly.
    if (range < max(fxaa_thr_min, lMax * fxaa_thr)) return uv;

    float lNW = tpLuma(uv + float2(-gPx.x,  gPx.y));
    float lNE = tpLuma(uv + float2( gPx.x,  gPx.y));
    float lSW = tpLuma(uv + float2(-gPx.x, -gPx.y));
    float lSE = tpLuma(uv + float2( gPx.x, -gPx.y));

    float lNS = lN + lS;
    float lWE = lW + lE;
    float lNWSW = lNW + lSW, lNESE = lNE + lSE;
    float lNWNE = lNW + lNE, lSWSE = lSW + lSE;

    // Second derivative across each axis: which way does the luma actually step?
    float edgeH = abs(-2.0 * lW + lNWSW) + abs(-2.0 * lC + lNS) * 2.0 + abs(-2.0 * lE + lNESE);
    float edgeV = abs(-2.0 * lS + lSWSE) + abs(-2.0 * lC + lWE) * 2.0 + abs(-2.0 * lN + lNWNE);
    bool horz = edgeH >= edgeV;

    float l1 = horz ? lS : lW;
    float l2 = horz ? lN : lE;
    float g1 = l1 - lC;
    float g2 = l2 - lC;

    bool steep1 = abs(g1) >= abs(g2);
    float gScaled = 0.25 * max(abs(g1), abs(g2));

    float stepLen = horz ? gPx.y : gPx.x;
    float lAvg;
    if (steep1) { stepLen = -stepLen; lAvg = 0.5 * (l1 + lC); }
    else        {                     lAvg = 0.5 * (l2 + lC); }

    // Sit on the edge itself, half a pixel off the centre, and walk from there.
    float2 cur = uv;
    if (horz) cur.y += stepLen * 0.5; else cur.x += stepLen * 0.5;

    float2 off = horz ? float2(gPx.x, 0.0) : float2(0.0, gPx.y);
    float2 uv1 = cur - off;
    float2 uv2 = cur + off;

    float e1 = tpLuma(uv1) - lAvg;
    float e2 = tpLuma(uv2) - lAvg;
    bool r1 = abs(e1) >= gScaled;
    bool r2 = abs(e2) >= gScaled;
    if (!r1) uv1 -= off;
    if (!r2) uv2 += off;

    // The search. `steps` is the quality tier: each extra step doubles the length of edge the
    // filter can still resolve correctly, and edges longer than the search simply fall back to
    // the sub-pixel term rather than breaking.
    [loop]
    for (int i = 0; i < 12; i++)
    {
        if (i >= steps || (r1 && r2)) break;
        // Accelerating stride: near the pixel the search must be exact, far from it a coarse
        // step is enough, and this is what lets four iterations cover a long silhouette.
        float q = (i < 2) ? 1.5 : ((i < 4) ? 2.0 : 4.0);
        if (!r1) { e1 = tpLuma(uv1) - lAvg; r1 = abs(e1) >= gScaled; if (!r1) uv1 -= off * q; }
        if (!r2) { e2 = tpLuma(uv2) - lAvg; r2 = abs(e2) >= gScaled; if (!r2) uv2 += off * q; }
    }

    float d1 = horz ? (uv.x - uv1.x) : (uv.y - uv1.y);
    float d2 = horz ? (uv2.x - uv.x) : (uv2.y - uv.y);
    bool dir1 = d1 < d2;

    float edgeLen = d1 + d2;
    float pixOff = -min(d1, d2) / max(edgeLen, 1e-6) + 0.5;

    // Only shift when this pixel is on the side of the edge that is actually changing; without
    // this test the filter pulls both sides toward each other and thickens every silhouette.
    bool lCsmaller = lC < lAvg;
    bool correct = ((dir1 ? e1 : e2) < 0.0) != lCsmaller;
    float finalOff = correct ? pixOff : 0.0;

    // Sub-pixel term: catches single-pixel features the edge search cannot see at all, which in
    // this frame means the specular glints and the caustic cusps.
    float lAvgAll = (2.0 * (lNS + lWE) + lNWSW + lNESE) * (1.0 / 12.0);
    float sub1 = saturate(abs(lAvgAll - lC) / max(range, 1e-5));
    float sub2 = (-2.0 * sub1 + 3.0) * sub1 * sub1;
    finalOff = max(finalOff, sub2 * sub2 * fxaa_sharp);

    float2 outUv = uv;
    if (horz) outUv.y += finalOff * stepLen; else outUv.x += finalOff * stepLen;
    return outUv;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 res = _Resolution.xy;
    float2 uv = ((float2)tid.xy + 0.5) / res;
    gPx = 1.0 / res;

    int mode = (int)aa_mode;

    // ---- antialias: resolve to a SAMPLE POSITION, not yet to a colour
    float2 sUv = uv;
    if (mode == 2) sUv = tpFXAA(uv, 2);
    else if (mode == 3) sUv = tpFXAA(uv, 4);

    // ---- lateral chromatic aberration
    //
    // Real lenses focus the short wavelengths nearer than the long ones, so the fringing is
    // RADIAL and grows toward the corners while the centre stays clean. A uniform offset across
    // the frame reads as a broken video signal instead of as glass.
    //
    // Sampled around the antialiased position rather than around the raw pixel, so red and blue
    // inherit the resolve instead of arriving with the staircase still in them.
    float3 c;
    float2 rd = uv - 0.5;
    float rr = saturate(length(rd) * 1.42);
    float caMag = ca_amount * pow(rr, max(ca_falloff, 0.01)) * 0.004;

    if (caMag > 1e-6)
    {
        float2 caOff = rd * caMag;
        c = float3(tpFetch(sUv + caOff).r, tpFetch(sUv).g, tpFetch(sUv - caOff).b);
    }
    else
    {
        c = tpFetch(sUv);
    }

    // ---- legacy gradient filter, kept as mode 1 so the two can be compared directly
    if (mode == 1 && aa_amount > 0.001)
    {
        float3 lw = float3(0.2126, 0.7152, 0.0722);
        float lC = dot(c, lw);
        float lL = tpLuma(uv - float2(gPx.x, 0));
        float lR = tpLuma(uv + float2(gPx.x, 0));
        float lD = tpLuma(uv - float2(0, gPx.y));
        float lU = tpLuma(uv + float2(0, gPx.y));

        float2 g = float2(lR - lL, lU - lD);
        if (length(g) > aa_threshold)
        {
            float2 dir = normalize(float2(-g.y, g.x)) * gPx * aa_amount;
            float3 nearPair = (tpFetch(uv + dir) + tpFetch(uv - dir)) * 0.5;
            float3 farPair = (tpFetch(uv + dir * 2.0) + tpFetch(uv - dir * 2.0)) * 0.5;
            float3 resolved = lerp(lerp(nearPair, farPair, 0.22), c,
                                   lerp(0.30, 0.86, saturate(aa_crispness)));
            float lMin = min(lC, min(min(lL, lR), min(lD, lU)));
            float lMax = max(lC, max(max(lL, lR), max(lD, lU)));
            c = lerp(c, resolved, saturate((lMax - lMin - aa_threshold)
                                         / max(aa_threshold * 3.0, 0.02)));
        }
    }

    // ---- bloom
    c += _Tex1.SampleLevel(LinearSampler, uv, 0).rgb * bloom;

    // ---- grade
    c *= exposure;
    float l = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = lerp(l.xxx, c, saturation);
    c = (c - 0.5) * contrast + 0.5 + lift;
    c = max(c, 0.0);

    // split tone, gentle: the reference's shadows sit cool and its highlights almost neutral
    float t = saturate(l * 1.6);
    c *= lerp(shadow_tint, highlight_tint, t);

    c = rollMax(c, roll_knee);

    // ---- lens
    float2 q = (uv - 0.5) * float2(res.x / max(res.y, 1.0), 1.0);
    c *= 1.0 - saturate(dot(q, q)) * vignette;

    OutputUAV[tid.xy] = float4(max(c, 0.0), 1.0);
}
