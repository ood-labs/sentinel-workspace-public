#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

float hashLocal(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float segmentDistanceT(float2 p, float2 a, float2 b, out float t)
{
    float2 pa = p - a;
    float2 ba = b - a;
    t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * t);
}

float2 animatedPosition(uint i, float phase)
{
    float2 pos = _Data0[i].position;
    float2 dir = normalize(_Data0[i].direction + float2(1e-6, 0.0));
    float weight = _Data0[i].weight;
    float motion = sin(phase * TAU + (float)i * 1.618) * (0.002 + weight * 0.008);
    return pos + dir * motion;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / _Resolution.y;
    float4 phaseState = _Tex0.Load(int3(0, 0, 0));
    float phase = phaseState.r;

    float nearest = 100.0;
    float second = 100.0;
    float2 nearestPos = 0.5;
    float2 nearestDir = float2(1.0, 0.0);
    float nearestWeight = 0.0;
    float nearestKind = 0.0;
    float nearestGroup = 0.0;
    float nearestActive = 0.0;
    float activeCount = 0.0;

    [loop]
    for (uint i = 0; i < 64u; ++i)
    {
        if (_Data0[i].active < 0.01) continue;
        activeCount += _Data0[i].active;

        float2 gpUv = animatedPosition(i, phase);
        float2 gp = (gpUv - 0.5) * float2(aspect, 1.0);
        float d = length(p - gp);
        if (d < nearest)
        {
            second = nearest;
            nearest = d;
            nearestPos = gpUv;
            nearestDir = normalize(_Data0[i].direction + float2(1e-6, 0.0));
            nearestWeight = _Data0[i].weight;
            nearestKind = _Data0[i].kind;
            nearestGroup = _Data0[i].group_id;
            nearestActive = _Data0[i].active;
        }
        else if (d < second)
        {
            second = d;
        }
    }

    float activeEnvelope = smoothstep(0.06, 0.92, nearestActive);
    float finiteInfluence = smoothstep(influence_radius, 0.0, nearest) * activeEnvelope;
    float2 warpDir = nearestDir / float2(aspect, 1.0);
    float groupSign = fmod(nearestGroup, 2.0) < 0.5 ? -1.0 : 1.0;
    float2 warp = warpDir * slice_displacement * finiteInfluence * nearestWeight * groupSign;

    float row = floor(uv.y * slice_rows);
    float rowNoise = hashLocal(row * 1.713 + floor(phase * 8.0));
    float tearGate = step(tear_threshold, rowNoise) * finiteInfluence;
    float tearOffset = (rowNoise - 0.5) * tear_amount * tearGate;

    if (render_mode == 0)
    {
        warp.x += tearOffset;
    }
    else if (render_mode == 1)
    {
        float quantized = floor((nearestGroup + phase * 2.0) * 3.0) / 3.0;
        warp += nearestDir.yx * float2(1.0, -1.0) * slice_displacement * 0.7 * sin(quantized);
        warp.x += tearOffset * 0.45;
    }
    else
    {
        float cellPolarity = fmod(nearestGroup, 3.0) - 1.0;
        warp += float2(cellPolarity, -groupSign) * slice_displacement * finiteInfluence * 0.34;
        float band = step(0.5, frac(uv.y * slice_rows * 0.5 + nearestGroup * 0.17));
        warp.x += tearOffset * band;
    }

    float2 perfDelta = (uv - performance_xy) * float2(aspect, 1.0);
    float perfRadius = 0.04 + performance_pressure * 0.28;
    float perfField = smoothstep(perfRadius, 0.0, length(perfDelta));
    float2 perfTangent = normalize(float2(-perfDelta.y, perfDelta.x) + float2(1e-6, 0.0));
    warp += perfTangent / float2(aspect, 1.0) * performance_pressure * perfField * 0.028;

    float2 sampleUv = saturate(uv + warp);
    float3 source = _Tex1.SampleLevel(LinearSampler, sampleUv, 0).rgb;
    float mono = dot(source, float3(0.2126, 0.7152, 0.0722));
    mono = saturate((mono - black_level) / max(white_level - black_level, 1e-4));
    float levels = max(posterize_levels, 2.0);
    mono = floor(mono * levels) / (levels - 1.0);

    float boundaryMetric = abs(second - nearest);
    float cellBoundaryWide = 1.0 - smoothstep(cell_line_width * 1.4, cell_line_width * 5.2, boundaryMetric);
    float cellBoundaryFine = 1.0 - smoothstep(cell_line_width * 0.18, cell_line_width * 0.95, boundaryMetric);
    float3 col = mono.xxx * source_gain;
    col += cellBoundaryWide * cell_edge_gain * 0.30 * activeEnvelope;
    col += cellBoundaryFine * cell_edge_gain * 1.35 * activeEnvelope;

    float web = 0.0;
    float redWeb = 0.0;
    [loop]
    for (uint j = 0; j < 63u; ++j)
    {
        if (_Data0[j].active < 0.01 || _Data0[j + 1u].active < 0.01) continue;

        float2 aUv = animatedPosition(j, phase);
        float2 bUv = animatedPosition(j + 1u, phase);
        float2 a = (aUv - 0.5) * float2(aspect, 1.0);
        float2 b = (bUv - 0.5) * float2(aspect, 1.0);
        if (length(b - a) > connectivity_radius) continue;
        float t;
        float d = segmentDistanceT(p, a, b, t);
        float sameGroup = 1.0 - step(0.25, abs(_Data0[j].group_id - _Data0[j + 1u].group_id));
        float lineMask = smoothstep(web_width * px * 1.7, web_width * px * 0.35, d);
        float dash = step(dash_ratio, frac(t * dash_count - phase * dash_speed + _Data0[j].group_id * 0.13));
        float strength = min(_Data0[j].weight, _Data0[j + 1u].weight) *
                         min(_Data0[j].active, _Data0[j + 1u].active);
        web += lineMask * dash * strength * lerp(0.18, 1.0, sameGroup);
        redWeb += lineMask * dash * strength * step(0.5, max(_Data0[j].kind, _Data0[j + 1u].kind));
    }

    float featureMark = 0.0;
    float featureSites = 0.0;
    float redMark = 0.0;
    float redSites = 0.0;
    [loop]
    for (uint k = 0; k < 64u; ++k)
    {
        if (_Data0[k].active < 0.01) continue;
        float2 gpUv = animatedPosition(k, phase);
        float2 gp = (gpUv - 0.5) * float2(aspect, 1.0);
        float2 gd = normalize(_Data0[k].direction * float2(aspect, 1.0) + float2(1e-6, 0.0));
        float t;
        float d = segmentDistanceT(p, gp - gd * 0.006, gp + gd * (0.012 + _Data0[k].weight * 0.025), t);
        float mark = smoothstep(mark_width * px * 1.8, mark_width * px * 0.35, d);
        float siteDistance = length(p - gp);
        float siteCore = smoothstep(1.35 * px, 0.28 * px, siteDistance);
        float siteRing = 1.0 - smoothstep(0.55 * px, 1.45 * px, abs(siteDistance - 3.8 * px));
        float site = saturate(siteCore + siteRing * 0.72);
        float recordEnvelope = smoothstep(0.03, 0.88, _Data0[k].active);
        featureMark += mark * _Data0[k].weight * recordEnvelope;
        featureSites += site * lerp(0.55, 1.0, _Data0[k].weight) * recordEnvelope;
        redMark += mark * step(0.5, _Data0[k].kind) * recordEnvelope;
        redSites += site * step(0.5, _Data0[k].kind) * recordEnvelope;
    }

    col += saturate(web) * web_gain;
    col += saturate(featureMark) * mark_gain;
    col += saturate(featureSites) * mark_gain * 1.15;

    // Accent color has a semantic job: it marks only records originating from
    // the real Features line output (plus an explicit performance gesture).
    // Voronoi/cell structure remains monochrome, regardless of response weight.
    float sparseRed = saturate(redWeb + redMark + redSites);
    float perfCross = max(
        smoothstep(1.5 * px, 0.2 * px, abs(perfDelta.x)) * step(abs(perfDelta.y), 0.018),
        smoothstep(1.5 * px, 0.2 * px, abs(perfDelta.y)) * step(abs(perfDelta.x), 0.018)
    ) * step(0.001, performance_pressure);
    sparseRed = saturate(sparseRed + perfCross);
    col = lerp(col, red_ink, saturate(sparseRed * red_amount));

    float scanCut = step(0.5, frac(uv.y * _Resolution.y * 0.5)) * scanline_cut;
    col = max(col - scanCut, 0.0);
    if (invert_output != 0) col = 1.0 - col;

    float vignette = smoothstep(1.1, 0.3, length((uv - 0.5) * float2(0.82, 1.0)));
    col *= lerp(0.72, 1.0, vignette);
    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
