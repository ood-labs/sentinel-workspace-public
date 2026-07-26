RWTexture2D<float4> OutputUAV : register(u0);

float reliefLuma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float2 reliefWorldToUv(float2 worldPosition)
{
    return worldPosition / float2(2.56, 1.44) + 0.5;
}

float4 reliefMap(float2 worldPosition)
{
    float2 mapUv = reliefWorldToUv(worldPosition);
    return _Tex1.SampleLevel(LinearSampler, mapUv, 0);
}

float reliefSurface(float2 worldPosition)
{
    return base_depth + reliefMap(worldPosition).r * height_gain;
}

float3 reliefNormal(float2 worldPosition)
{
    uint fieldWidth = 0;
    uint fieldHeight = 0;
    _Tex1.GetDimensions(fieldWidth, fieldHeight);
    float2 fieldTexel = 1.0 / max(float2(fieldWidth, fieldHeight), float2(1.0, 1.0));
    float2 worldStep = fieldTexel * float2(2.56, 1.44);
    float heightLeft = reliefSurface(worldPosition - float2(worldStep.x, 0.0));
    float heightRight = reliefSurface(worldPosition + float2(worldStep.x, 0.0));
    float heightUp = reliefSurface(worldPosition - float2(0.0, worldStep.y));
    float heightDown = reliefSurface(worldPosition + float2(0.0, worldStep.y));
    return normalize(float3(heightLeft - heightRight,
                            heightUp - heightDown,
                            max(worldStep.x + worldStep.y, 0.001)));
}

float segmentDistance(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float3 programColor = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float2 chamberCoord = (uv - chamber_center) / max(chamber_size, float2(0.02, 0.02));
    float chamberInside = step(abs(chamberCoord.x), 0.5) * step(abs(chamberCoord.y), 0.5);
    float2 viewCoord = float2(chamberCoord.x * 2.0, -chamberCoord.y * 2.0);

    float yaw = view_yaw;
    float horizontalDistance = 2.9;
    float3 cameraPosition = float3(sin(yaw) * horizontalDistance,
                                   -cos(yaw) * horizontalDistance,
                                   0.72 + view_pitch * 2.35);
    float3 cameraTarget = float3(0.0, 0.0, 0.22);
    float3 forward = normalize(cameraTarget - cameraPosition);
    float3 right = normalize(cross(forward, float3(0.0, 0.0, 1.0)));
    float3 up = normalize(cross(right, forward));

    float3 rayOrigin = cameraPosition
                     + right * viewCoord.x * 0.96
                     + up * viewCoord.y * 0.72;
    float3 rayDirection = forward;

    float travel = 0.0;
    float previousTravel = 0.0;
    float previousDistance = 10.0;
    float hit = 0.0;
    float3 hitPosition = float3(0.0, 0.0, 0.0);

    [loop]
    for (int stepIndex = 0; stepIndex < 64; ++stepIndex)
    {
        float3 probe = rayOrigin + rayDirection * travel;
        float insidePlate = step(abs(probe.x), 1.28) * step(abs(probe.y), 0.72);
        float signedDistance = probe.z - reliefSurface(probe.xy);

        if (insidePlate > 0.5 && signedDistance <= 0.0 && previousDistance > 0.0)
        {
            float lowTravel = previousTravel;
            float highTravel = travel;
            [unroll]
            for (int refineIndex = 0; refineIndex < 5; ++refineIndex)
            {
                float middleTravel = (lowTravel + highTravel) * 0.5;
                float3 middleProbe = rayOrigin + rayDirection * middleTravel;
                float middleDistance = middleProbe.z - reliefSurface(middleProbe.xy);
                if (middleDistance > 0.0) lowTravel = middleTravel;
                else highTravel = middleTravel;
            }
            travel = (lowTravel + highTravel) * 0.5;
            hitPosition = rayOrigin + rayDirection * travel;
            hit = 1.0;
            break;
        }

        previousTravel = travel;
        previousDistance = signedDistance;
        travel += max(abs(signedDistance) * 0.34, 0.015);
        if (travel > 6.0) break;
    }

    float3 color = programColor;
    color *= 1.0 - chamberInside * chamber_dim;

    if (hit > 0.5 && chamberInside > 0.5)
    {
        float2 reliefUv = reliefWorldToUv(hitPosition.xy);
        float4 mapValue = reliefMap(hitPosition.xy);
        float3 sourceColor = _Tex0.SampleLevel(LinearSampler, reliefUv, 0).rgb;
        float sourceInk = reliefLuma(sourceColor);
        float3 normal = reliefNormal(hitPosition.xy);
        float3 lightDirection = normalize(float3(-0.45, -0.62, 0.78));
        float diffuse = saturate(dot(normal, lightDirection));
        float rim = pow(saturate(1.0 - dot(normal, -rayDirection)), 3.0);
        float heightValue = mapValue.r;

        float contourPhase = frac(heightValue * contour_count + relief_phase);
        float contourDistance = min(contourPhase, 1.0 - contourPhase);
        float contour = smoothstep(contour_width, contour_width * 0.18, contourDistance);
        float2 gridPhase = abs(frac(reliefUv * float2(18.0, 10.0)) - 0.5);
        float gridDistance = min(gridPhase.x, gridPhase.y);
        float gridInk = smoothstep(0.035, 0.008, gridDistance);

        float3 material = paper_color
                        * (0.055 + sourceInk * 0.48)
                        * (0.24 + diffuse * 0.86);
        material += paper_color * (contour * contour_gain
                                 + gridInk * grid_gain
                                 + mapValue.g * ridge_ink
                                 + rim * 0.16);
        float kineticAccent = saturate(mapValue.b * impact_ink);
        material = lerp(material, accent_color, kineticAccent);

        if (relief_mode == 1)
        {
            material = lerp(material,
                            paper_color * (0.08 + gridInk * 0.72 + contour * 0.32),
                            0.52);
        }
        else if (relief_mode == 2)
        {
            float wireGate = saturate(contour * 0.72 + gridInk * 0.82
                                    + mapValue.g * 0.48 + rim * 0.28);
            material = lerp(programColor * 0.18, paper_color * wireGate,
                            saturate(wireGate + 0.18));
            material = lerp(material, accent_color, kineticAccent);
        }

        color = lerp(color, material, specimen_gain);
    }

    float edgeDistance = min(0.5 - abs(chamberCoord.x), 0.5 - abs(chamberCoord.y));
    float frame = smoothstep(0.009, 0.0015, abs(edgeDistance)) * chamberInside;
    float screenAspect = _Resolution.x / max(_Resolution.y, 1.0);
    float hairline = 1.1 / _Resolution.y;
    float2 chamberHalfSize = chamber_size * 0.5;
    float2 absoluteChamberDelta = abs(uv - chamber_center);
    float cornerDistance = length((absoluteChamberDelta - chamberHalfSize)
                                * float2(screenAspect, 1.0));
    float cornerRing = smoothstep(hairline * 1.15, hairline * 0.14,
                                  abs(cornerDistance - 0.0052));
    float cornerCore = smoothstep(hairline * 1.55, hairline * 0.16,
                                  cornerDistance);
    float horizontalBracket = smoothstep(hairline * 1.15, hairline * 0.12,
                                         abs(absoluteChamberDelta.y - chamberHalfSize.y))
                            * step(chamberHalfSize.x - 0.016, absoluteChamberDelta.x)
                            * step(absoluteChamberDelta.x, chamberHalfSize.x + 0.0015);
    float verticalBracket = smoothstep(hairline * 1.15, hairline * 0.12,
                                       abs(absoluteChamberDelta.x - chamberHalfSize.x))
                          * step(chamberHalfSize.y - 0.023, absoluteChamberDelta.y)
                          * step(absoluteChamberDelta.y, chamberHalfSize.y + 0.0015);
    float cornerBrackets = max(horizontalBracket, verticalBracket);
    float scanY = frac(relief_phase * 1.7 + 0.13) - 0.5;
    float scanLine = smoothstep(0.007, 0.001,
                                abs(chamberCoord.y - scanY))
                   * chamberInside;
    color = max(color, paper_color
                * saturate(frame * 0.42 + cornerBrackets * 0.64
                         + cornerRing * 0.52 + cornerCore * 0.68));
    color = lerp(color, accent_color, scanLine * scan_gain);

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
