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
    float relief = sampledDepth(uv) * relief_amount;
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
        float relief = sampledDepth(uv) * relief_amount;
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
    return min(contentDistance, housingDistance);
}

int surfaceMaterial(float3 p)
{
    float2 halfSize = panelHalfSize();
    float contentDistance = mapContent(p, halfSize);
    float housingDistance = mapFrame(p, halfSize);
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
                   bool frameSurface)
{
    float edgeFactor = frameSurface ? 0.0 : cutoutEdgeFactor(uv);
    float2 colorUv = edgeRefinedColorUv(uv, edgeFactor);
    float3 videoAlbedo = adjustAlbedo(_Tex0.SampleLevel(LinearSampler, saturate(colorUv), 0).rgb);
    float3 albedo = frameSurface ? frame_color : videoAlbedo;
    float3 flatNormal = float3(0.0, 0.0, p.z >= 0.0 ? 1.0 : -1.0);
    float effectiveNormalStrength = normal_strength * (1.0 - edgeFactor * normal_edge_soften);
    n = frameSurface ? normalize(n) : normalize(lerp(flatNormal, n, effectiveNormalStrength));
    if (!frameSurface && normal_front_bias > 0.001)
        n = normalize(lerp(n, flatNormal, normal_front_bias));

    if (display_mode == 1) return pow(saturate(albedo), (1.0 / max(output_gamma, 0.1)).xxx);
    if (display_mode == 2) return frameSurface ? 0.5.xxx : sampledDepth(uv).xxx;
    if (display_mode == 3) return n * 0.5 + 0.5;
    if (display_mode == 4) return frameSurface ? 1.0.xxx : geometryCoverage(uv).xxx;

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
    if (!frameSurface)
    {
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
    float3 color = shadeRelief(hitPosition, normal, -rayDirection, uv, frameSurface);
    OutputUAV[DTid.xy] = float4(color, 1.0);
}
