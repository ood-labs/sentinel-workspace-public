RWTexture2D<float4> OutputUAV : register(u0);

#include "distortion.hlsli"

float2 rotate2(float2 p, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float boxDistance2D(float2 p, float2 halfSize)
{
    float2 q = abs(p) - halfSize;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float roundedBoxDistance2D(float2 p, float2 halfSize, float radius)
{
    float r = min(max(radius, 0.0), min(halfSize.x, halfSize.y) * 0.95);
    return boxDistance2D(p, max(halfSize - r, 0.001.xx)) - r;
}

float2 panelHalfSize()
{
    float sourceWidth, sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    float sourceAspect = max(sourceWidth, 1.0) / max(sourceHeight, 1.0);
    return float2(panel_scale * sourceAspect, panel_scale);
}

float2 panelUv(float2 panelPosition, float2 halfSize)
{
    // Sentinel's camera-facing panel basis runs opposite texture U. Reverse U
    // once here so both color and depth remain registered and read correctly.
    float2 uv = float2(
        0.5 - panelPosition.x / max(halfSize.x * 2.0, 0.001),
        0.5 - panelPosition.y / max(halfSize.y * 2.0, 0.001));

    float zoom = max(framing_zoom, 1.0);
    float2 margin = 0.5.xx * (1.0 - 1.0 / zoom);
    uv = 0.5.xx + (uv - 0.5.xx) / zoom + framing_pan * margin;
    return uv;
}

float2 panelPositionFromUv(float2 uv, float2 halfSize)
{
    float zoom = max(framing_zoom, 1.0);
    float2 margin = 0.5.xx * (1.0 - 1.0 / zoom);
    float2 baseUv = 0.5.xx + (uv - 0.5.xx - framing_pan * margin) * zoom;
    return float2(
        (0.5 - baseUv.x) * halfSize.x * 2.0,
        (0.5 - baseUv.y) * halfSize.y * 2.0);
}

float orientedDepth(float rawDepth)
{
    return depth_invert != 0 ? 1.0 - rawDepth : rawDepth;
}

float remapDepth(float rawDepth)
{
    float d = saturate((orientedDepth(rawDepth) - depth_black) / max(depth_white - depth_black, 0.001));
    return pow(max(d, 0.0001), max(depth_gamma, 0.05));
}

float sampledDepth(float2 uv)
{
    return remapDepth(_Tex1.SampleLevel(LinearSampler, saturate(uv), 0).r);
}

float tracerSurfaceMask(float2 uv)
{
    float2 sampleUv = saturate(uv);
    float3 baseColor = _Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb;
    float3 tracedColor = _Tex3.SampleLevel(LinearSampler, sampleUv, 0).rgb;
    float difference = length(tracedColor - baseColor);
    return smoothstep(0.018, 0.22, difference);
}

float detectionFrameMask(float2 uv)
{
    if (detections_enabled == 0) return 0.0;

    float result = 0.0;
    uint count = min(_Data0_Count, 16u);
    [loop]
    for (uint i = 0; i < count; ++i)
    {
        float confidence = saturate(_Data0[i].confidence);
        if (confidence < detection_confidence) continue;

        float2 boundsMin = saturate(float2(_Data0[i].x1, _Data0[i].y1));
        float2 boundsMax = saturate(float2(_Data0[i].x2, _Data0[i].y2));
        float2 lo = min(boundsMin, boundsMax);
        float2 hi = max(boundsMin, boundsMax);
        float inside = step(lo.x, uv.x) * step(uv.x, hi.x)
                     * step(lo.y, uv.y) * step(uv.y, hi.y);
        float edgeDistance = min(
            min(abs(uv.x - lo.x), abs(uv.x - hi.x)),
            min(abs(uv.y - lo.y), abs(uv.y - hi.y)));
        float border = inside * (1.0 - smoothstep(
            detection_line_width,
            detection_line_width * 1.75,
            edgeDistance));
        result = max(result, border * smoothstep(detection_confidence, 1.0, confidence));
    }
    return saturate(result);
}

float3 classPalette(float classId)
{
    float slot = fmod(abs(classId), 8.0);
    if (slot < 1.0) return float3(1.0, 0.28, 0.08);
    if (slot < 2.0) return float3(0.12, 0.72, 1.0);
    if (slot < 3.0) return float3(0.32, 1.0, 0.36);
    if (slot < 4.0) return float3(1.0, 0.78, 0.12);
    if (slot < 5.0) return float3(0.86, 0.28, 1.0);
    if (slot < 6.0) return float3(0.16, 1.0, 0.82);
    if (slot < 7.0) return float3(1.0, 0.42, 0.68);
    return float3(0.60, 0.68, 1.0);
}

float3 detectionColorAtUv(float2 uv)
{
    if (detection_color_mode == 0) return detection_color;
    float bestEdge = 10000.0;
    float bestConfidence = 0.0;
    float bestClass = 0.0;
    uint count = min(_Data0_Count, 16u);
    [loop]
    for (uint i = 0; i < count; ++i)
    {
        float confidence = saturate(_Data0[i].confidence);
        if (confidence < detection_confidence) continue;
        float2 lo = min(saturate(float2(_Data0[i].x1, _Data0[i].y1)),
                        saturate(float2(_Data0[i].x2, _Data0[i].y2)));
        float2 hi = max(saturate(float2(_Data0[i].x1, _Data0[i].y1)),
                        saturate(float2(_Data0[i].x2, _Data0[i].y2)));
        float inside = step(lo.x, uv.x) * step(uv.x, hi.x)
                     * step(lo.y, uv.y) * step(uv.y, hi.y);
        float edge = min(min(abs(uv.x - lo.x), abs(uv.x - hi.x)),
                         min(abs(uv.y - lo.y), abs(uv.y - hi.y)));
        if (inside > 0.5 && edge < bestEdge)
        {
            bestEdge = edge;
            bestConfidence = confidence;
            bestClass = _Data0[i].classId;
        }
    }
    if (detection_color_mode == 2)
        return lerp(float3(1.0, 0.12, 0.04), float3(0.16, 1.0, 0.32), bestConfidence);
    return classPalette(bestClass);
}

float integratedRelief(float2 uv)
{
    if (integration_mode == 1) return sampledDepth(uv) * relief_amount;
    return sampledDepth(uv) * relief_amount
         + tracerSurfaceMask(uv) * tracer_relief
         + detectionFrameMask(uv) * detection_relief;
}

float surfaceZ(float2 panelPosition, float2 halfSize);

float contentSurfaceZ(float2 panelPosition, float2 halfSize)
{
    float z = surfaceZ(panelPosition, halfSize);
    if (frame_mode == 2 || frame_mode == 3) z -= inset_depth;
    return z;
}

float capsuleDistance(float3 p, float3 a, float3 b, float radius)
{
    float3 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 0.00001));
    return length(p - lerp(a, b, t)) - radius;
}

float detectionVolume(float3 p, float2 halfSize)
{
    if (integration_mode != 1 || detections_enabled == 0) return 10000.0;

    float result = 10000.0;
    uint count = min(_Data0_Count, 12u);
    [loop]
    for (uint i = 0; i < count; ++i)
    {
        float confidence = saturate(_Data0[i].confidence);
        if (confidence < detection_confidence) continue;

        float2 boundsMin = saturate(float2(_Data0[i].x1, _Data0[i].y1));
        float2 boundsMax = saturate(float2(_Data0[i].x2, _Data0[i].y2));
        float2 lo = min(boundsMin, boundsMax);
        float2 hi = max(boundsMin, boundsMax);
        float2 centerUv = (lo + hi) * 0.5;
        float2 center = panelPositionFromUv(centerUv, halfSize);
        float2 cornerUv[4] = {
            float2(lo.x, lo.y), float2(hi.x, lo.y),
            float2(hi.x, hi.y), float2(lo.x, hi.y) };
        float3 corner[4];
        float topZ = -10000.0;
        [unroll]
        for (int c = 0; c < 4; ++c)
        {
            float2 cornerPosition = panelPositionFromUv(cornerUv[c], halfSize);
            corner[c] = float3(cornerPosition, contentSurfaceZ(cornerPosition, halfSize));
            topZ = max(topZ, corner[c].z);
        }
        topZ += detection_relief;

        float2 railHalf = max(abs(panelPositionFromUv(hi, halfSize) - center), detection_line_width.xx);
        float railRadius = detection_geometry_mode == 1
            ? max(detection_line_width * 0.15, 0.00012)
            : max(detection_line_width * 0.5, 0.004);
        float outer = boxDistance2D(p.xy - center, railHalf + railRadius.xx);
        float inner = -boxDistance2D(p.xy - center, max(railHalf - railRadius.xx, 0.001.xx));
        float ring = max(outer, inner);
        float topRail = max(ring, abs(p.z - topZ) - railRadius);
        result = min(result, topRail);

        if (detection_depth_struts != 0)
        {
            [unroll]
            for (int c = 0; c < 4; ++c)
                result = min(result, capsuleDistance(p, corner[c], float3(corner[c].xy, topZ), railRadius));
        }
        if (detection_geometry_mode == 0 && detection_corner_dots != 0)
        {
            [unroll]
            for (int c = 0; c < 4; ++c)
                result = min(result, length(p - float3(corner[c].xy, topZ)) - detection_dot_radius);
        }
    }
    return result;
}

float tracerVolume(float3 p, float2 halfSize)
{
    if (integration_mode != 1 || tracer_relief <= 0.0001) return 10000.0;
    float2 uv = panelUv(p.xy, halfSize);
    float mask = tracerSurfaceMask(uv);
    float fieldDistance = (0.42 - mask) * 0.08;
    float centerZ = contentSurfaceZ(p.xy, halfSize) + tracer_relief;
    float slabDistance = abs(p.z - centerZ) - 0.012;
    return max(fieldDistance, slabDistance);
}

float edgeMask(float2 uv)
{
    float edgeDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    return smoothstep(0.0, max(edge_fade, 0.001), edgeDistance);
}

float depthCutoutCoverage(float2 uv)
{
    float rawDepth = orientedDepth(_Tex1.SampleLevel(LinearSampler, saturate(uv), 0).r);
    return smoothstep(depth_black, depth_black + max(cutout_feather, 0.001), rawDepth);
}

float matteValue(float2 uv)
{
    float matte = _Tex2.SampleLevel(LinearSampler, saturate(uv), 0).r;
    if (mask_invert != 0) matte = 1.0 - matte;
    return matte;
}

float matteCutoutCoverage(float2 uv)
{
    float threshold = saturate(mask_threshold + mask_erode);
    return smoothstep(threshold, threshold + max(cutout_feather, 0.001), matteValue(uv));
}

float geometryCoverage(float2 uv)
{
    if (cutout_mode == 1) return depthCutoutCoverage(uv);
    if (cutout_mode == 2) return matteCutoutCoverage(uv);
    if (cutout_mode == 3) return min(depthCutoutCoverage(uv), matteCutoutCoverage(uv));
    return 1.0;
}

float cutoutDistance(float2 uv)
{
    if (cutout_mode == 0) return -1.0;
    // Approximate a signed boundary around the selected foreground. The
    // front/back distances still move rays quickly through empty regions;
    // this term only controls the silhouette crossing near the volume.
    return (0.5 - geometryCoverage(uv)) * cutout_wall_width;
}

float surfaceZ(float2 panelPosition, float2 halfSize)
{
    float2 uv = panelUv(panelPosition, halfSize);
    float mask = edgeMask(uv);
    float relief = integratedRelief(uv);
    if (relief_direction == 1)
        return -(recess_amount + relief) * mask;
    return relief * mask;
}

float mapReliefLocal(float3 p, float2 halfSize)
{
    float2 uv = panelUv(p.xy, halfSize);
    float side = max(boxDistance2D(p.xy, halfSize), cutoutDistance(uv));
    float frontZ = surfaceZ(p.xy, halfSize);
    float mappedDistance;

    if (mirror_z != 0)
    {
        float mask = edgeMask(uv);
        float relief = integratedRelief(uv);
        float signedRelief = relief_direction == 1
            ? -(recess_amount + relief) * mask
            : relief * mask;
        float halfDepth = max(mirror_core + signedRelief, 0.015);
        mappedDistance = max(side, abs(p.z) - halfDepth);
    }
    else
    {
        // Keep the volume closed even when an inward surface is deeper than the
        // nominal panel thickness. There is no separate rear block to intersect.
        float backZ = min(-panel_thickness, frontZ - 0.035);
        float backDistance = backZ - p.z;
        float frontDistance = p.z - frontZ;
        mappedDistance = max(side, max(backDistance, frontDistance));
    }

    return mappedDistance;
}

float mapContent(float3 p, float2 halfSize)
{
    // Inverse-domain deformation: move the sample point, then evaluate the
    // original relief volume. This deforms the entire signed-distance field.
    float3 q = lrDomainDistort(p, 1.0);

    // Wall modes offset the relief relative to the rigid wall plane. Positive
    // values recess it; negative values pull it out into the room.
    if (frame_mode == 2 || frame_mode == 3) q.z += inset_depth;

    // The warp breaks the exact-distance guarantee. This conservative
    // Lipschitz compensation prevents the ray marcher from stepping over it.
    return mapReliefLocal(q, halfSize) * lrDistortLip(1.0);
}

float mapFrameLocal(float3 p, float2 panelHalf)
{
    float2 innerHalf = panelHalf + max(frame_gap, 0.0).xx;

    float outerExpansion = frame_mode >= 2
        ? max(wall_extent, frame_width)
        : max(frame_width, 0.01);
    float2 outerHalf = innerHalf + outerExpansion.xx;

    float outerRadius = min(frame_corner_radius, min(outerHalf.x, outerHalf.y) * 0.45);
    float innerRadius = min(frame_corner_radius * 0.65, min(innerHalf.x, innerHalf.y) * 0.45);
    float outerDistance = roundedBoxDistance2D(p.xy, outerHalf, outerRadius);
    float innerDistance = roundedBoxDistance2D(p.xy, innerHalf, innerRadius);
    float ringDistance = max(outerDistance, -innerDistance);

    // Extrude the 2D ring into a real closed volume, then round the meeting
    // between its face and side walls for a machined exhibit-frame bevel.
    float depth = max(frame_depth, 0.01);
    float centerZ = frame_front_z - depth * 0.5;
    float slabDistance = abs(p.z - centerZ) - depth * 0.5;
    float2 extrusion = float2(ringDistance, slabDistance);
    float distanceToFrame = length(max(extrusion, 0.0))
        + min(max(extrusion.x, extrusion.y), 0.0);
    return distanceToFrame - min(frame_bevel, depth * 0.35);
}

float mapFrame(float3 p, float2 panelHalf)
{
    if (frame_mode == 0) return 10000.0;
    // Breakthrough mode deliberately keeps the wall rigid and planar even
    // while the relief on top of it undergoes extreme distortion.
    if (frame_distort != 0 && frame_mode != 3)
        return mapFrameLocal(lrDomainDistort(p, 1.0), panelHalf) * lrDistortLip(1.0);
    return mapFrameLocal(p, panelHalf);
}

float mapRelief(float3 p)
{
    float2 halfSize = panelHalfSize();
    float contentDistance = mapContent(p, halfSize);
    float housingDistance = mapFrame(p, halfSize);
    float separateDetection = detectionVolume(p, halfSize);
    float separateTracer = tracerVolume(p, halfSize);
    return min(min(contentDistance, housingDistance), min(separateDetection, separateTracer));
}

int surfaceMaterial(float3 p)
{
    float2 halfSize = panelHalfSize();
    float contentDistance = mapContent(p, halfSize);
    float housingDistance = mapFrame(p, halfSize);
    float detectionDistance = detectionVolume(p, halfSize);
    float tracerDistance = tracerVolume(p, halfSize);
    if (detectionDistance <= contentDistance && detectionDistance <= housingDistance && detectionDistance <= tracerDistance) return 2;
    if (tracerDistance <= contentDistance && tracerDistance <= housingDistance) return 3;
    return housingDistance <= contentDistance ? 1 : 0;
}

float3 reliefNormalAt(float3 p, float e)
{
    float3 n = 0.0;
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float3 d = float3(
            (i & 1) ? 1.0 : -1.0,
            (i & 2) ? 1.0 : -1.0,
            (i == 0 || i == 3) ? 1.0 : -1.0);
        n += d * mapRelief(p + d * e);
    }
    return normalize(n);
}

float3 reliefNormal(float3 p, float travel)
{
    // Widening a single SDF gradient rejects high-frequency depth/matte noise
    // without doubling the ray-marched field evaluations per shaded pixel.
    float smoothScale = lerp(1.0, normal_smooth_radius, normal_smoothing);
    float sampleRadius = hit_epsilon * (1.5 + travel * 0.04)
        * normal_sample_scale * smoothScale;
    return reliefNormalAt(p, sampleRadius);
}

float3 housingNormal(float3 p, float travel)
{
    float2 halfSize = panelHalfSize();
    float e = hit_epsilon * (1.5 + travel * 0.04);
    float3 n = 0.0;
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float3 d = float3(
            (i & 1) ? 1.0 : -1.0,
            (i & 2) ? 1.0 : -1.0,
            (i == 0 || i == 3) ? 1.0 : -1.0);
        n += d * mapFrame(p + d * e, halfSize);
    }
    return normalize(n);
}

float ambientOcclusion(float3 p, float3 n)
{
    float occlusion = 0.0;
    float weight = 1.0;
    [unroll]
    for (int i = 1; i <= 5; ++i)
    {
        float distanceAlongNormal = 0.018 + i * 0.035;
        occlusion += max(distanceAlongNormal - mapRelief(p + n * distanceAlongNormal), 0.0) * weight;
        weight *= 0.62;
    }
    return saturate(1.0 - occlusion * ao_strength * 6.0);
}

float softShadow(float3 origin, float3 direction)
{
    if (shadows_enabled == 0) return 1.0;
    float visibility = 1.0;
    float travel = 0.018;
    [loop]
    for (int i = 0; i < 32; ++i)
    {
        float distanceToSurface = mapRelief(origin + direction * travel);
        if (distanceToSurface < hit_epsilon * 1.5) return 0.0;
        visibility = min(visibility, shadow_softness * distanceToSurface / max(travel, 0.001));
        travel += clamp(distanceToSurface * 0.65, 0.008, 0.16);
        if (travel > 5.0) break;
    }
    return saturate(visibility);
}

float3 cameraRay(float2 uv, out float3 rayOrigin)
{
    // Sentinel camera feature: DirectX NDC has +Y at the top of the viewport.
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nearWorld = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farWorld = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearWorld /= max(abs(nearWorld.w), 0.00001);
    farWorld /= max(abs(farWorld.w), 0.00001);
    rayOrigin = _CameraPos;
    return normalize(farWorld.xyz - nearWorld.xyz);
}

float3 keyLightDirection()
{
    float yaw = light_orbit.x;
    float elevation = light_orbit.y;
    return normalize(float3(
        sin(yaw) * cos(elevation),
        sin(elevation),
        cos(yaw) * cos(elevation)));
}

float3 adjustAlbedo(float3 sourceColor)
{
    float3 color = pow(saturate(sourceColor), max(input_gamma, 0.1).xxx);
    float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = lerp(luminance.xxx, color, saturation);
    return max(color * albedo_tint * color_gain, 0.0);
}

float cutoutEdgeFactor(float2 uv)
{
    if (cutout_mode == 0) return 0.0;
    float coverage = geometryCoverage(uv);
    float distanceFromBoundary = abs(coverage - 0.5);
    return 1.0 - smoothstep(0.0, max(normal_edge_width, 0.001), distanceFromBoundary);
}

float2 edgeRefinedColorUv(float2 uv, float edgeFactor)
{
    if ((cutout_mode != 2 && cutout_mode != 3) || edge_color_inset < 0.001 || edgeFactor < 0.001)
        return uv;

    float maskWidth, maskHeight;
    _Tex2.GetDimensions(maskWidth, maskHeight);
    float2 texel = 1.0 / max(float2(maskWidth, maskHeight), 1.0.xx);
    float2 gradient = float2(
        matteValue(uv + float2(texel.x, 0.0)) - matteValue(uv - float2(texel.x, 0.0)),
        matteValue(uv + float2(0.0, texel.y)) - matteValue(uv - float2(0.0, texel.y)));
    float gradientLength = length(gradient);
    if (gradientLength < 0.0001) return uv;
    return saturate(uv + gradient / gradientLength * texel * edge_color_inset * edgeFactor);
}

float3 shadeRelief(float3 p, float3 n, float3 viewDirection, float2 uv,
                   int materialId)
{
    bool frameSurface = materialId == 1;
    bool detectionSurface = materialId == 2;
    bool tracerSurface = materialId == 3;
    float edgeFactor = (frameSurface || detectionSurface || tracerSurface) ? 0.0 : cutoutEdgeFactor(uv);
    float2 colorUv = edgeRefinedColorUv(uv, edgeFactor);
    float3 videoAlbedo = adjustAlbedo(_Tex0.SampleLevel(LinearSampler, saturate(colorUv), 0).rgb);
    float3 tracedAlbedo = adjustAlbedo(_Tex3.SampleLevel(LinearSampler, saturate(colorUv), 0).rgb);
    float tracerMask = (!frameSurface && !detectionSurface && !tracerSurface) ? tracerSurfaceMask(colorUv) : 0.0;
    float detectionMask = (!frameSurface && !detectionSurface && !tracerSurface) ? detectionFrameMask(colorUv) : 0.0;
    float3 integratedAlbedo = lerp(videoAlbedo, tracedAlbedo, tracer_mix * tracerMask);
    integratedAlbedo = lerp(integratedAlbedo, detectionColorAtUv(colorUv), detectionMask);
    float3 localDetectionColor = detectionColorAtUv(uv);
    float3 albedo = frameSurface ? frame_color
        : detectionSurface ? localDetectionColor
        : tracerSurface ? tracedAlbedo
        : integratedAlbedo;
    float3 flatNormal = float3(0.0, 0.0, p.z >= 0.0 ? 1.0 : -1.0);
    float effectiveNormalStrength = normal_strength * (1.0 - edgeFactor * normal_edge_soften);
    n = frameSurface ? normalize(n) : normalize(lerp(flatNormal, n, effectiveNormalStrength));
    if (!frameSurface && normal_front_bias > 0.001)
        n = normalize(lerp(n, flatNormal, normal_front_bias));

    if (display_mode == 1) return pow(saturate(albedo), (1.0 / max(output_gamma, 0.1)).xxx);
    if (display_mode == 2) return (frameSurface || detectionSurface || tracerSurface) ? 0.5.xxx : sampledDepth(uv).xxx;
    if (display_mode == 3) return n * 0.5 + 0.5;
    if (display_mode == 4) return (frameSurface || detectionSurface || tracerSurface) ? 1.0.xxx : geometryCoverage(uv).xxx;

    float3 lightDirection = keyLightDirection();
    float diffuse = saturate(dot(n, lightDirection));
    float shadow = softShadow(p + n * hit_epsilon * 4.0, lightDirection);
    // The rigid wall has an analytically clean face and covers many pixels, so
    // avoid expensive relief AO queries across the entire wall.
    float ao = frameSurface ? 1.0 : max(ambientOcclusion(p, n), ao_floor);

    float3 halfVector = normalize(lightDirection + viewDirection);
    float localRoughness = frameSurface ? frame_roughness : roughness;
    float localSpecular = frameSurface ? frame_specular : specular_strength;
    float localMetallic = frameSurface ? frame_metallic : 0.0;
    float specularPower = lerp(128.0, 5.0, localRoughness * localRoughness);
    float fresnel = pow(1.0 - saturate(dot(n, viewDirection)), 5.0);
    float specularTerm = pow(saturate(dot(n, halfVector)), specularPower) * localSpecular;
    specularTerm *= lerp(0.35, 1.0, fresnel);

    float hemi = saturate(n.y * 0.5 + 0.5);
    float3 ambient = ambient_color * ambient_strength * lerp(0.55, 1.0, hemi);
    float3 direct = light_color * key_intensity * diffuse * shadow;
    float rim = pow(1.0 - saturate(dot(n, viewDirection)), rim_power) * rim_strength;

    float3 color = albedo * (ambient + direct) * ao;
    float3 specularColor = lerp(light_color, albedo * light_color, localMetallic);
    color += specularColor * specularTerm * shadow;
    color += rim_color * rim;
    if (detectionSurface)
    {
        color += localDetectionColor * (1.25 + detection_relief * 0.35);
    }
    else if (tracerSurface)
    {
        color += max(tracedAlbedo - videoAlbedo, 0.0) * tracer_emission;
    }
    else if (!frameSurface)
    {
        float3 tracerDelta = max(tracedAlbedo - videoAlbedo, 0.0);
        color += tracerDelta * tracer_emission * tracerMask;
        color += detection_color * (1.25 + detection_relief * 0.35) * detectionMask;
        // Keep matte/cutout boundaries and nearly perpendicular side walls
        // from collapsing to black without flattening the interior lighting.
        float sideFactor = 1.0 - abs(n.z);
        float fillAmount = edgeFactor * edge_fill_strength + sideFactor * side_fill_strength;
        color += albedo * (ambient_color + light_color * 0.2) * fillAmount;
    }

    float3 mapped = 1.0 - exp(-max(color, 0.0) * exposure);
    return pow(saturate(mapped), (1.0 / max(output_gamma, 0.1)).xxx);
}

float3 backgroundColor(float3 rayDirection)
{
    float gradient = saturate(rayDirection.y * 0.5 + 0.5);
    float3 background = lerp(background_bottom, background_top, gradient);
    float vignette = 1.0 - 0.18 * pow(saturate(1.0 - abs(rayDirection.z)), 2.0);
    return background * vignette;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y) return;

    float2 screenUv = ((float2)DTid.xy + 0.5) / _Resolution.xy;
    float3 rayOrigin;
    float3 rayDirection = cameraRay(screenUv, rayOrigin);

    float travel = 0.02;
    bool hit = false;
    [loop]
    for (int step = 0; step < 160; ++step)
    {
        if (step >= ray_steps) break;
        float distanceToSurface = mapRelief(rayOrigin + rayDirection * travel);
        if (distanceToSurface < hit_epsilon * (1.0 + travel * 0.03))
        {
            hit = true;
            break;
        }
        travel += max(distanceToSurface * march_safety, hit_epsilon * 0.65);
        if (travel > max_distance) break;
    }

    if (!hit)
    {
        OutputUAV[DTid.xy] = float4(backgroundColor(rayDirection), 1.0);
        return;
    }

    float3 hitPosition = rayOrigin + rayDirection * travel;
    int materialId = surfaceMaterial(hitPosition);
    bool frameSurface = materialId == 1;
    float3 normal;
    if (frameSurface && (frame_mode == 2 || frame_mode == 3))
        normal = float3(0.0, 0.0, hitPosition.z >= frame_front_z - frame_depth * 0.5 ? 1.0 : -1.0);
    else if (frameSurface)
        normal = housingNormal(hitPosition, travel);
    else
        normal = reliefNormal(hitPosition, travel);
    if (dot(normal, -rayDirection) < 0.0) normal = -normal;
    // Use the same deformed domain for texture, depth, and cutout lookup so
    // every input remains glued to the SDF through the animation.
    float3 materialPosition = lrDomainDistort(hitPosition, 1.0);
    float2 uv = panelUv(materialPosition.xy, panelHalfSize());
    float3 color = shadeRelief(hitPosition, normal, -rayDirection, uv, materialId);
    OutputUAV[DTid.xy] = float4(color, 1.0);
}
