RWTexture2D<float4> OutputUAV : register(u0);

struct GeodesicPoint
{
    float2 position;
    float progress;
    float confidence;
};

StructuredBuffer<GeodesicPoint> Geodesic : register(t1);

struct BreathState
{
    float breath_phase;
    float asymmetry_phase;
    float rupture_phase;
    float drift_phase;
    float valid;
    float eclipse_phase;
    float pad1;
    float pad2;
};

StructuredBuffer<BreathState> Breath : register(t2);

float depth_tilt_lobe_mask(float2 samplePoint, float centerAngle)
{
    float radius = length(samplePoint);
    float angular = cos(atan2(samplePoint.y, samplePoint.x) - centerAngle);
    float sector = pow(saturate(angular * 0.5 + 0.5), asymmetry_focus);
    float radial = smoothstep(
        asymmetry_inner_radius - 0.035,
        asymmetry_inner_radius + 0.055,
        radius);
    return sector * radial;
}

float depth_tilt_segment_distance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-7));
    return length(p - (a + ab * t));
}

float3 depth_tilt_sample(float2 uv, float2 texel, float radiusPx)
{
    float2 d = texel * radiusPx;
    float3 center = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 axial =
        _Tex0.SampleLevel(LinearSampler, uv + float2(d.x, 0.0), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv - float2(d.x, 0.0), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, d.y), 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv - float2(0.0, d.y), 0).rgb;
    float3 diagonal =
        _Tex0.SampleLevel(LinearSampler, uv + d * 0.7071, 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv - d * 0.7071, 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv + float2(d.x, -d.y) * 0.7071, 0).rgb +
        _Tex0.SampleLevel(LinearSampler, uv + float2(-d.x, d.y) * 0.7071, 0).rgb;
    return center * 0.28 + axial * 0.105 + diagonal * 0.075;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float driftPhase = frac(Breath[0].drift_phase + drift_phase_offset);
    float driftAngle = driftPhase * 6.28318530718;
    float2 driftShape = float2(
        cos(driftAngle) + 0.28 * cos(driftAngle * 2.0 + 1.1),
        0.58 * sin(driftAngle) - 0.22 * sin(driftAngle * 3.0));
    float2 compositionalDrift = driftShape * drift_amount;
    float2 p =
        (uv - float2(0.5, 0.5) - tilt_core) * float2(aspect, 1.0) -
        compositionalDrift;
    float breathValue = sin(Breath[0].breath_phase * 6.28318530718);
    float breathScale = max(0.82, 1.0 + breathValue * breath_amount);
    float2 breathedP = p / breathScale;
    float asymmetryWave =
        0.5 + 0.5 * sin(Breath[0].asymmetry_phase * 6.28318530718);
    float lobeCenter =
        (1.57079632679 + _Time * 0.10) / 5.0 +
        asymmetry_lobe * 1.25663706144;
    float inverseLobeMask = depth_tilt_lobe_mask(breathedP, lobeCenter);
    float inverseLobeScale =
        1.0 + asymmetry_amount * asymmetryWave * inverseLobeMask;
    float eclipseWave =
        smoothstep(
            0.06,
            0.94,
            0.5 +
                0.5 *
                    sin(
                        frac(Breath[0].eclipse_phase + eclipse_phase_offset) *
                        6.28318530718));
    float eclipseCenter =
        (1.57079632679 + _Time * 0.10) / 5.0 +
        eclipse_lobe * 1.25663706144;
    float eclipseAngular =
        cos(atan2(breathedP.y, breathedP.x) - eclipseCenter);
    float eclipseSector =
        pow(saturate(eclipseAngular * 0.5 + 0.5), 5.0);
    float eclipseRadial =
        smoothstep(0.12, 0.21, length(breathedP));
    float eclipseScale =
        1.0 -
        eclipse_retraction *
            eclipseWave *
            eclipseSector *
            eclipseRadial;
    float2 sceneP =
        breathedP /
        max(inverseLobeScale * eclipseScale, 0.72);

    float confidence = smoothstep(0.08, 0.48, azimuth_confidence);
    float2 forward = normalize(float2(azimuth_x, azimuth_y) + float2(1e-5, 0.0));
    float2 side = float2(-forward.y, forward.x);
    float2 local = float2(dot(sceneP, side), dot(sceneP, forward));

    // Inverse projective mapping: the live azimuth side is the near,
    // emphasized plane; the opposite lobes compress into depth.
    float projective = perspective_tilt * confidence;
    float denominator = max(0.62, 1.0 - projective * local.y);
    float2 sourceLocal = local / denominator;
    float2 sourceP = side * sourceLocal.x + forward * sourceLocal.y;
    float2 sourceUv = sourceP / float2(aspect, 1.0) + float2(0.5, 0.5) + tilt_core;

    float focalDistance = abs(local.y - focus_depth);
    float defocus = smoothstep(focus_width, focus_width + 0.30, focalDistance);
    float radialSoften = smoothstep(0.34, 0.72, length(sceneP)) * outer_soften;
    float blurRadius = defocus * dof_pixels * confidence + radialSoften;

    float3 sharp = _Tex0.SampleLevel(LinearSampler, sourceUv, 0).rgb;
    float3 softened = depth_tilt_sample(sourceUv, texel, max(blurRadius, 0.01));
    float sharpWarm = saturate(sharp.r - max(sharp.g, sharp.b));
    float softWarm = saturate(softened.r - max(softened.g, softened.b));
    float inheritedWarm = smoothstep(0.025, 0.14, max(sharpWarm, softWarm));

    float transmission = inverseLobeMask * asymmetryWave * lobe_transmission;
    float lx0 = dot(
        _Tex0.SampleLevel(LinearSampler, sourceUv - float2(texel.x * 2.0, 0.0), 0).rgb,
        float3(0.299, 0.587, 0.114));
    float lx1 = dot(
        _Tex0.SampleLevel(LinearSampler, sourceUv + float2(texel.x * 2.0, 0.0), 0).rgb,
        float3(0.299, 0.587, 0.114));
    float ly0 = dot(
        _Tex0.SampleLevel(LinearSampler, sourceUv - float2(0.0, texel.y * 2.0), 0).rgb,
        float3(0.299, 0.587, 0.114));
    float ly1 = dot(
        _Tex0.SampleLevel(LinearSampler, sourceUv + float2(0.0, texel.y * 2.0), 0).rgb,
        float3(0.299, 0.587, 0.114));
    float2 materialDelta = float2(lx1 - lx0, ly1 - ly0);
    float silhouetteRegion = smoothstep(0.30, 0.62, length(sceneP));
    float silhouetteEdge =
        smoothstep(
            silhouette_gate,
            silhouette_gate + 0.08,
            length(materialDelta)) *
        silhouetteRegion *
        silhouette_clarity;
    softened = lerp(softened, sharp, silhouetteEdge);
    float2 materialGradient = normalize(materialDelta + float2(1e-5, 0.0));
    float2 refractedUv =
        sourceUv +
        materialGradient * texel * refraction_pixels * transmission;
    float3 refracted = depth_tilt_sample(
        refractedUv,
        texel,
        max(refractive_soften + blurRadius * 0.25, 0.01));
    float refractedLum = dot(refracted, float3(0.299, 0.587, 0.114));
    float3 transmitted =
        lerp(
            refractedLum * 0.82 * float3(0.96, 0.98, 0.94),
            refracted,
            transmission_detail);
    sharp = lerp(sharp, transmitted, transmission);
    softened = lerp(softened, transmitted, transmission);

    // Reconstruct across the inherited straight needle before drawing the
    // contour-following path, so the composition retains one warm event.
    float2 repairOffset =
        side * (accent_repair_pixels / _Resolution.y) / float2(aspect, 1.0);
    float3 repairA = _Tex0.SampleLevel(LinearSampler, sourceUv + repairOffset, 0).rgb;
    float3 repairB = _Tex0.SampleLevel(LinearSampler, sourceUv - repairOffset, 0).rgb;
    float3 repaired = (repairA + repairB) * 0.5;
    float repairedLum = dot(repaired, float3(0.299, 0.587, 0.114));
    repaired = repairedLum * float3(0.96, 0.98, 0.94);

    float3 color = softened;
    color = lerp(color, repaired, inheritedWarm * accent_repair);

    float hushSignal = smoothstep(
        hush_floor,
        hush_floor + hush_softness,
        dot(color, float3(0.299, 0.587, 0.114)));
    color *= lerp(1.0, hushSignal, eclipseWave * hush_amount);

    float eclipseRadius = length(sceneP);
    float eclipseFront = 0.11 + eclipse_reach * eclipseWave;
    float eclipseCore =
        1.0 -
        smoothstep(
            eclipseFront - eclipse_softness,
            eclipseFront + eclipse_softness,
            eclipseRadius);
    float eclipsePenumbra =
        1.0 -
        smoothstep(
            eclipseFront + eclipse_softness,
            eclipseFront + eclipse_softness + 0.18,
            eclipseRadius);
    float eclipseCoreMask =
        eclipseSector *
        saturate(eclipseCore + eclipsePenumbra * 0.30) *
        eclipse_depth;
    float eclipseBodyMask =
        eclipseSector *
        eclipseWave *
        eclipse_depth *
        eclipse_dissolution *
        smoothstep(0.13, 0.25, eclipseRadius);
    float eclipseMask = saturate(max(eclipseCoreMask, eclipseBodyMask));
    color *= 1.0 - eclipseMask;

    float rupturePhaseDistance = abs(Breath[0].rupture_phase - 0.5);
    float automaticRupture =
        1.0 -
        smoothstep(
            rupture_duration,
            rupture_duration + 0.04,
            rupturePhaseDistance);
    float ruptureEnvelope = max(automaticRupture, rupture_force);
    float ruptureCenter =
        (1.57079632679 + _Time * 0.10) / 5.0 +
        rupture_lobe * 1.25663706144;
    float2 ruptureDirection = float2(cos(ruptureCenter), sin(ruptureCenter));
    float2 ruptureNormal = float2(-ruptureDirection.y, ruptureDirection.x);
    float ruptureForward = dot(breathedP, ruptureDirection);
    float ruptureProgress = saturate(
        (ruptureForward - rupture_inner_radius) /
        max(rupture_outer_radius - rupture_inner_radius, 1e-4));
    float ruptureOpening =
        rupture_width *
        lerp(0.22, 1.60, smoothstep(0.0, 1.0, ruptureProgress));
    float ruptureBend =
        rupture_width * 0.42 * sin(ruptureProgress * 3.14159265359);
    float ruptureLateral =
        abs(dot(breathedP, ruptureNormal) - ruptureBend);
    float ruptureRay =
        smoothstep(
            rupture_inner_radius - rupture_feather,
            rupture_inner_radius + rupture_feather,
            ruptureForward) *
        (1.0 -
         smoothstep(
             rupture_outer_radius - rupture_feather,
             rupture_outer_radius + rupture_feather,
             ruptureForward));
    float ruptureCleft =
        (1.0 -
         smoothstep(
             ruptureOpening,
             ruptureOpening + rupture_feather,
             ruptureLateral)) *
        ruptureRay *
        ruptureEnvelope *
        rupture_strength;
    color *= 1.0 - ruptureCleft;

    float geodesicMask = 0.0;
    float geodesicGroove = 0.0;
    float geodesicBevel = 0.0;
    [unroll]
    for (uint i = 0; i < 23; ++i)
    {
        GeodesicPoint a = Geodesic[i];
        GeodesicPoint b = Geodesic[i + 1];

        float2 localA = float2(dot(a.position, side), dot(a.position, forward));
        float2 localB = float2(dot(b.position, side), dot(b.position, forward));
        float2 projectedA = localA / max(0.62, 1.0 + projective * localA.y);
        float2 projectedB = localB / max(0.62, 1.0 + projective * localB.y);
        float2 unscaledPointA = side * projectedA.x + forward * projectedA.y;
        float2 unscaledPointB = side * projectedB.x + forward * projectedB.y;
        float lobeScaleA =
            1.0 +
            asymmetry_amount *
            asymmetryWave *
            depth_tilt_lobe_mask(unscaledPointA, lobeCenter);
        float lobeScaleB =
            1.0 +
            asymmetry_amount *
            asymmetryWave *
            depth_tilt_lobe_mask(unscaledPointB, lobeCenter);
        float2 pointA = unscaledPointA * lobeScaleA * breathScale;
        float2 pointB = unscaledPointB * lobeScaleB * breathScale;

        float distanceToPath = depth_tilt_segment_distance(p, pointA, pointB);
        float segmentDepth = (localA.y + localB.y) * 0.5;
        float nearPlane = smoothstep(-0.30, 0.30, segmentDepth);
        float depthPresence = lerp(
            1.0,
            0.42 + nearPlane * 0.58,
            geodesic_depth_integration);
        float widthScale = lerp(
            1.0,
            0.62 + nearPlane * 0.46,
            geodesic_depth_integration);
        float farSoftness =
            geodesic_far_soften *
            (1.0 - nearPlane) *
            geodesic_depth_integration;
        float stroke = 1.0 - smoothstep(
            (geodesic_width * widthScale) / _Resolution.y,
            (geodesic_width * widthScale + 1.55 + farSoftness) / _Resolution.y,
            distanceToPath);
        float groove = 1.0 - smoothstep(
            (geodesic_width * widthScale + groove_width) / _Resolution.y,
            (geodesic_width * widthScale + groove_width + 1.65 + farSoftness) /
                _Resolution.y,
            distanceToPath);
        float2 bevelOffset =
            normalize(float2(-0.55, -0.83)) * (1.10 / _Resolution.y);
        float bevelDistance =
            depth_tilt_segment_distance(p + bevelOffset, pointA, pointB);
        float bevelGroove = 1.0 - smoothstep(
            (geodesic_width * widthScale + groove_width) / _Resolution.y,
            (geodesic_width * widthScale + groove_width + 1.65 + farSoftness) /
                _Resolution.y,
            bevelDistance);
        float pathFade =
            smoothstep(0.0, 0.08, a.progress) *
            (1.0 - smoothstep(0.86, 1.0, a.progress));
        geodesicMask = max(
            geodesicMask,
            stroke * pathFade * depthPresence * min(a.confidence, b.confidence));
        geodesicGroove = max(
            geodesicGroove,
            groove * pathFade * depthPresence * min(a.confidence, b.confidence));
        geodesicBevel = max(
            geodesicBevel,
            bevelGroove *
                pathFade *
                depthPresence *
                min(a.confidence, b.confidence));
    }
    float surfaceBeforeGroove = dot(color, float3(0.299, 0.587, 0.114));
    float umbraPathVisibility =
        1.0 - eclipseMask * eclipse_filament_occlusion;
    float bevelHighlight = saturate(geodesicBevel - geodesicGroove);
    color +=
        bevelHighlight *
        groove_bevel *
        umbraPathVisibility *
        (1.0 - surfaceBeforeGroove) *
        float3(0.96, 0.98, 0.94);
    color *= 1.0 - geodesicGroove * groove_depth;
    float surfaceLum = dot(color, float3(0.299, 0.587, 0.114));
    float contourGap = 1.0 - smoothstep(0.44, 0.86, surfaceLum);
    float weaveVisibility = lerp(1.0, contourGap, ridge_occlusion);
    float substrateVisibility =
        lerp(
            geodesic_substrate_minimum,
            1.0,
            smoothstep(
                geodesic_substrate_floor,
                geodesic_substrate_floor + geodesic_substrate_softness,
                surfaceBeforeGroove));
    float filamentLight =
        0.58 + 0.42 * smoothstep(0.06, 0.62, surfaceBeforeGroove);
    float3 warmPath =
        lerp(
            float3(0.55, 0.018, 0.005),
            float3(1.0, 0.095, 0.014),
            filamentLight);
    color = lerp(
        color,
        warmPath,
        geodesicMask *
            geodesic_gain *
            warm_clarity *
            weaveVisibility *
            substrateVisibility *
            umbraPathVisibility);

    float inside =
        step(0.0, sourceUv.x) * step(sourceUv.x, 1.0) *
        step(0.0, sourceUv.y) * step(sourceUv.y, 1.0);
    color *= inside;

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
