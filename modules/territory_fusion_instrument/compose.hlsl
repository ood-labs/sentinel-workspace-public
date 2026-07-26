RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));

    float3 loom = _Tex0.SampleLevel(PointSampler, uv, 0).rgb;
    float3 seismic = _Tex1.SampleLevel(PointSampler, uv, 0).rgb;
    float3 seismicRight = _Tex1.SampleLevel(PointSampler, uv + float2(texel.x, 0.0), 0).rgb;
    float3 seismicDown = _Tex1.SampleLevel(PointSampler, uv + float2(0.0, texel.y), 0).rgb;
    float loomCenter = luminance(loom);
    float loomRight = luminance(_Tex0.SampleLevel(PointSampler, uv + float2(texel.x, 0.0), 0).rgb);
    float loomDown = luminance(_Tex0.SampleLevel(PointSampler, uv + float2(0.0, texel.y), 0).rgb);
    float2 loomGradient = float2(loomRight - loomCenter, loomDown - loomCenter);

    float seismicEnergy = saturate(max(seismic.r, max(seismic.g, seismic.b)) * aperture_gain);
    float seismicEnergyRight = saturate(max(seismicRight.r, max(seismicRight.g, seismicRight.b)) * aperture_gain);
    float seismicEnergyDown = saturate(max(seismicDown.r, max(seismicDown.g, seismicDown.b)) * aperture_gain);
    float seismicGradient = saturate(length(float2(
        seismicEnergyRight - seismicEnergy,
        seismicEnergyDown - seismicEnergy)) * 9.0);
    float seismicContour = 1.0 - smoothstep(0.028, 0.085, abs(seismicEnergy - 0.52));
    float aperture = smoothstep(0.035, 0.42, seismicEnergy);
    float displacementScale = warp_strength * (0.003 + 0.020 * aperture) *
                              (0.45 + 0.55 * master_envelope);
    float2 warpedUv = saturate(uv + loomGradient * displacementScale);
    float3 towers = _Tex2.SampleLevel(PointSampler, warpedUv, 0).rgb;
    float towerLuma = luminance(towers);

    float3 neutral = float3(0.88, 0.90, 0.86);
    float3 warm = accent;
    float3 col = towers;

    float contrastPivot = 0.34;
    col = saturate((col - contrastPivot) * tower_contrast + contrastPivot);

    float registration = smoothstep(0.08, 0.68, loomCenter) * loom_gain;
    float darkCarrier = registration * (1.0 - smoothstep(0.12, 0.72, towerLuma));
    col += neutral * darkCarrier * 0.48;

    float3 apertureInterior = col * (0.62 + loomCenter * 1.15);
    apertureInterior += neutral * registration * 0.32;
    apertureInterior = lerp(apertureInterior, warm, seismicEnergy * 0.20);
    col = lerp(col, apertureInterior, aperture);

    float openSpace = 1.0 - smoothstep(0.16, 0.74, towerLuma);
    float warmEdge = saturate(seismicGradient + seismicContour * 0.52);
    float occludedEdge = warmEdge * lerp(0.16, 0.90, openSpace);
    col = lerp(col, warm, occludedEdge * (0.42 + 0.22 * master_pulse));

    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / max(_Resolution.y, 1.0);
    float edgeX = 0.5 * aspect - 0.045;
    float edgeY = 0.452;
    float frameX = (1.0 - smoothstep(px, px * 2.0, abs(abs(p.x) - edgeX))) * step(abs(p.y), edgeY);
    float frameY = (1.0 - smoothstep(px, px * 2.0, abs(abs(p.y) - edgeY))) * step(abs(p.x), edgeX);
    col += neutral * saturate(frameX + frameY) * 0.28;

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
