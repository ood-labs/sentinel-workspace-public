#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float2 pdRotate(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float pdBox(float2 p, float2 halfExtent)
{
    float2 d = abs(p) - halfExtent;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float pdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float pdStroke(float distanceValue, float width)
{
    float aa = 1.5 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(width, width + aa, distanceValue);
}

float pdFilled(float signedDistance)
{
    float aa = 1.5 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(-aa, aa, signedDistance);
}

float pdRing(float distanceValue, float radius, float width)
{
    return pdStroke(abs(distanceValue - radius), width);
}

float pdHash(float n)
{
    return frac(sin(n * 117.37 + 19.17) * 43758.5453);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    p -= leverage_point * float2(aspect, 1.0) * 0.18;
    p /= max(0.25, world_scale);

    float t = frac(phase);
    float theta = t * AN_TAU;

    float3 voidColor = float3(0.003, 0.0035, 0.003);
    float3 substrate = float3(0.88, 0.895, 0.86);
    float3 graphite = float3(0.13, 0.145, 0.135);
    float3 ash = float3(0.36, 0.375, 0.355);
    float3 liability = liability_color;
    float3 color = voidColor;

    // Perspective ledger: the only background structure, converging on leverage.
    float2 vanishing = leverage_point * float2(aspect, 1.0) * 0.35;
    float ledger = 0.0;
    [unroll]
    for (int railIndex = 0; railIndex < 13; ++railIndex)
    {
        float u = ((float)railIndex / 12.0) * 2.0 - 1.0;
        float2 a = float2(u * 1.25, 0.62);
        float2 b = vanishing + float2(u * 0.035, -0.08);
        ledger = max(ledger, pdStroke(pdSegment(p, a, b), 0.00075));
    }
    float horizonY = -0.42 + 0.035 * sin(theta);
    [unroll]
    for (int horizonIndex = 0; horizonIndex < 8; ++horizonIndex)
    {
        float fy = (float)horizonIndex / 7.0;
        float y = lerp(horizonY, 0.58, fy * fy);
        ledger = max(ledger, pdStroke(abs(p.y - y), 0.00065));
    }
    color += graphite * ledger * ledger_gain;

    // The obligation plates: asymmetric folded slabs orbiting a shared but displaced liability.
    float plateBody = 0.0;
    float plateEdge = 0.0;
    float plateFold = 0.0;
    float voidBodies = 0.0;
    float voidEdges = 0.0;
    float hingeMarks = 0.0;
    float debtBars = 0.0;

    [loop]
    for (int i = 0; i < 12; ++i)
    {
        if (i >= plate_count) break;

        float fi = (float)i;
        float countSafe = max(1.0, (float)plate_count);
        float indexPhase = fi / countSafe;
        float stagger = an_stagger_index(fi, countSafe, 0.22);
        float localT = frac(t - stagger);
        float orbitalNoise = an_loop_noise(localT, 1.0, 0.72, fi + 0.31);
        float angle = indexPhase * AN_TAU + theta * (0.13 + 0.017 * fmod(fi, 3.0));
        float orbit = orbit_radius * (0.52 + 0.48 * orbitalNoise);
        float2 center = float2(cos(angle), sin(angle * 1.17)) * orbit;
        center.x += 0.16 * sin(theta * 2.0 + fi * 1.73);
        center.y += 0.06 * cos(theta * 3.0 - fi);

        float plateAngle = -angle * 0.34 + torsion * (indexPhase - 0.5) + sin(theta + fi) * 0.13;
        float2 q = pdRotate(p - center, plateAngle);
        q.x += q.y * (0.15 + 0.32 * sin(fi * 2.11 + theta)) * fold_bias;

        float2 size = float2(
            0.075 + 0.052 * pdHash(fi + 3.0),
            0.026 + 0.032 * pdHash(fi + 17.0)
        ) * plate_scale;
        float plateDistance = pdBox(q, size);
        float body = pdFilled(plateDistance);
        float edge = pdStroke(abs(plateDistance), 0.0016);

        // One side is clipped into a fold; the fold gives Corners a meaningful hinge role.
        float foldAxis = q.x + q.y * (0.55 + 0.2 * sin(fi));
        float foldMask = body * smoothstep(-0.006, 0.012, foldAxis - size.x * 0.14);
        float foldLine = body * pdStroke(abs(foldAxis - size.x * 0.14), 0.0012);

        // Counterparty voids are black bodies with white registrations, useful as bounded blobs.
        float2 voidCenter = float2(-size.x * 0.22, size.y * (pdHash(fi + 41.0) - 0.5));
        float voidRadius = min(size.x, size.y) * lerp(0.24, 0.54, pdHash(fi + 59.0));
        float voidDistance = length(q - voidCenter);
        float voidBody = body * (1.0 - smoothstep(voidRadius - 0.002, voidRadius + 0.002, voidDistance));
        float voidEdge = body * pdRing(voidDistance, voidRadius, 0.0011);

        // Ledger bars are attached to their plate, never decorative global telemetry.
        float barRegion = body * step(size.x * 0.05, q.x) * step(abs(q.y), size.y * 0.55);
        float barPattern = step(0.48 + 0.18 * pdHash(fi + 77.0), frac((q.x + q.y * 0.22) * 96.0 + fi * 0.17));

        plateBody = max(plateBody, body);
        plateEdge = max(plateEdge, edge);
        plateFold = max(plateFold, foldMask);
        hingeMarks = max(hingeMarks, foldLine);
        voidBodies = max(voidBodies, voidBody);
        voidEdges = max(voidEdges, voidEdge);
        debtBars = max(debtBars, barRegion * barPattern);
    }

    color = lerp(color, substrate, plateBody * plate_opacity);
    color = lerp(color, ash, plateFold * fold_shade);
    color = lerp(color, voidColor, voidBodies * void_gain);
    color += substrate * (plateEdge * edge_gain + hingeMarks * hinge_gain + voidEdges * 0.72);
    color = lerp(color, graphite, debtBars * bar_gain);

    // A central rotating liability aperture binds the separate obligations into one score.
    float2 apertureP = pdRotate(p - vanishing * 0.45, -theta * 0.07);
    float apertureDistance = length(apertureP * float2(0.82, 1.0));
    float apertureRadius = 0.105 + 0.018 * sin(theta * 2.0);
    float aperture = pdRing(apertureDistance, apertureRadius, 0.0022);
    float apertureTicks = 0.0;
    [unroll]
    for (int tickIndex = 0; tickIndex < 16; ++tickIndex)
    {
        float tickAngle = ((float)tickIndex / 16.0) * AN_TAU + theta * 0.09;
        float2 axis = float2(cos(tickAngle), sin(tickAngle));
        apertureTicks = max(
            apertureTicks,
            pdStroke(pdSegment(apertureP, axis * 0.124, axis * (0.137 + 0.018 * ((tickIndex & 3) == 0))), 0.0010)
        );
    }
    color += substrate * (aperture * aperture_gain + apertureTicks * tick_gain);

    // A phase-locked margin call traverses the architecture and earns the only warm color.
    float callX = lerp(-1.15, 1.15, t);
    float call = pdStroke(abs(p.x - callX), 0.0014);
    float callMask = smoothstep(0.58, 0.44, abs(p.y));
    float callPulse = pdRing(length(p - vanishing), 0.055 + 0.42 * t, 0.0017);
    float liabilitySignal = max(call * callMask, callPulse * (1.0 - t));
    color += liability * liabilitySignal * liability_gain;

    // Hard binary discipline is deliberate: it creates tractable data for the real Features node.
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    float snapped = smoothstep(binary_threshold - 0.018, binary_threshold + 0.018, luma);
    float3 binaryColor = lerp(voidColor, substrate, snapped);
    color = lerp(color, binaryColor, binary_snap);
    color += liability * liabilitySignal * liability_gain * (1.0 - binary_snap * 0.65);

    float frameDistance = abs(pdBox(p, float2(0.85, 0.468)));
    float frame = pdStroke(frameDistance, 0.0014);
    color += substrate * frame * frame_gain;

    float vignette = saturate(1.0 - length(p * float2(0.55, 0.92)) * 0.48);
    color *= lerp(0.28, 1.0, vignette);
    color *= exposure;

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
