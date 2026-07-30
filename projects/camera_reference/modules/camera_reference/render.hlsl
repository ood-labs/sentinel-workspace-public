// Sentinel Native Camera Reference
// An analytic ground-plane intersection keeps the reference nearly empty:
// no SDF, no raymarch, no authored camera, and no scene geometry.

RWTexture2D<float4> OutputUAV : register(u0);

float gridLine(float value, float spacing, float derivativeWidth)
{
    float cell = abs(frac(value / spacing + 0.5) - 0.5) * spacing;
    return 1.0 - smoothstep(derivativeWidth, derivativeWidth * 2.0, cell);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 screenUV = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

    float4 nearWorld = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farWorld = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearWorld /= nearWorld.w;
    farWorld /= farWorld.w;

    float3 rayOrigin = _CameraPos;
    float3 rayDirection = normalize(farWorld.xyz - nearWorld.xyz);

    float3 color = float3(0.0, 0.0, 0.0);
    float depthValue = 0.0;

    if (rayDirection.y < -0.00001)
    {
        float travel = -rayOrigin.y / rayDirection.y;
        if (travel > 0.0 && travel < _CameraFar)
        {
            float3 worldPos = rayOrigin + rayDirection * travel;
            float pixelFootprint = max(0.0004,
                travel / max(_Resolution.y, 1.0) * 1.8 * line_width);

            float fineX = gridLine(worldPos.x, grid_spacing, pixelFootprint);
            float fineZ = gridLine(worldPos.z, grid_spacing, pixelFootprint);
            float fineGrid = max(fineX, fineZ);

            float majorSpacing = grid_spacing * 10.0;
            float majorX = gridLine(worldPos.x, majorSpacing, pixelFootprint * 1.6);
            float majorZ = gridLine(worldPos.z, majorSpacing, pixelFootprint * 1.6);
            float majorGrid = max(majorX, majorZ);

            float axisWidth = pixelFootprint * 1.35;
            float xAxis = 1.0 - smoothstep(axisWidth, axisWidth * 2.0, abs(worldPos.z));
            float zAxis = 1.0 - smoothstep(axisWidth, axisWidth * 2.0, abs(worldPos.x));

            float distanceFade = exp(-travel * grid_fade);
            float horizonFade = smoothstep(0.015, 0.16, -rayDirection.y);
            float fade = distanceFade * horizonFade;

            float gridValue = fineGrid * 0.16 + majorGrid * 0.34;
            color += gridValue.xxx * grid_strength * fade;
            color += float3(0.92, 0.025, 0.018) *
                     xAxis * axis_strength * fade;
            color += float3(0.018, 0.12, 0.95) *
                     zAxis * axis_strength * fade;

            depthValue = 1.0 - saturate(travel / _CameraFar);
        }
    }

    color = 1.0 - exp(-color * exposure);
    color = pow(saturate(color), 1.0 / 2.2);
    OutputUAV[pixel] = float4(color, depthValue);
}
