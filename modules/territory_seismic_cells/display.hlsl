RWTexture2D<float4> OutputUAV : register(u0);

float lineMask(float value, float width)
{
    return 1.0 - smoothstep(width, width * 1.8, abs(value));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    uint fieldWidth, fieldHeight;
    _Tex0.GetDimensions(fieldWidth, fieldHeight);
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    int2 fieldCell = int2(saturate(uv) * float2(fieldWidth - 1, fieldHeight - 1));
    float4 field = _Tex0.Load(int3(fieldCell, 0));
    float heightValue = field.x;
    float velocity = field.y;
    float activity = field.z;

    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / max(_Resolution.y, 1.0);
    float3 warm = accent;
    float3 neutral = float3(0.84, 0.86, 0.82);
    float3 col = float3(0.0035, 0.004, 0.0035);

    float contourPhase = frac(heightValue * contour_density);
    float contours = min(contourPhase, 1.0 - contourPhase);
    float contourMask = 1.0 - smoothstep(0.010, 0.030, contours);
    float activeField = smoothstep(0.006, 0.075, abs(heightValue)) *
                        smoothstep(0.008, 0.11, activity);
    col += neutral * contourMask * activeField * (0.18 + activity * 0.70);

    float signBand = smoothstep(0.0, 0.45, saturate(heightValue * 2.5));
    col += warm * signBand * activeField * (0.06 + activity * 0.28);

    float2 cellUv = frac(uv * float2(32.0 * aspect, 18.0));
    float cellEdge = min(min(cellUv.x, 1.0 - cellUv.x), min(cellUv.y, 1.0 - cellUv.y));
    float grid = 1.0 - smoothstep(px * 0.5, px * 2.0, cellEdge);
    col += neutral * grid * 0.024;

    float tau = 6.28318530718;
    float2 sourceUv = float2(
        0.5 + 0.285 * sin(master_phase * tau),
        0.5 + 0.235 * sin(master_phase * tau * 1.5 + 1.2));
    float2 sourceP = (sourceUv - 0.5) * float2(aspect, 1.0);
    float sourceDistance = length(p - sourceP);
    float sourceMark = lineMask(sourceDistance - 0.025, px * 1.5);
    float cross = lineMask((p - sourceP).x, px) * step(abs((p - sourceP).y), 0.045);
    cross += lineMask((p - sourceP).y, px) * step(abs((p - sourceP).x), 0.045);
    col = lerp(col, warm, saturate(sourceMark + cross));

    float edgeX = 0.5 * aspect - 0.048;
    float edgeY = 0.452;
    float frame = lineMask(abs(p.x) - edgeX, px) * step(abs(p.y), edgeY);
    frame += lineMask(abs(p.y) - edgeY, px) * step(abs(p.x), edgeX);
    col += neutral * frame * 0.35;

    float velocityTrace = smoothstep(0.0, 0.12, abs(velocity));
    col += warm * velocityTrace * activity * activeField * (0.05 + 0.16 * master_pulse);
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
