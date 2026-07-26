RWTexture2D<float4> OutputUAV : register(u0);

float hashCell(float2 p)
{
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float boxMask(float2 p, float2 halfSize, float softness)
{
    float2 d = abs(p) - halfSize;
    return 1.0 - smoothstep(0.0, softness, max(d.x, d.y));
}

float lineSegment(float2 p, float2 a, float2 b, float width)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001));
    return 1.0 - smoothstep(width, width * 1.8, length(pa - ba * h));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)DTid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 gridSize = float2((float)cell_columns, max(4.0, round((float)cell_columns / aspect)));
    float2 cellCoord = uv * gridSize;
    float2 cellId = floor(cellCoord);
    float2 q = frac(cellCoord) - 0.5;

    float2 idNorm = (cellId + 0.5) / gridSize;
    float waveCoord = idNorm.x;
    if (mechanism_family == 1)
        waveCoord = frac(idNorm.x * 0.65 + idNorm.y * 0.85);
    else if (mechanism_family == 2)
        waveCoord = length((idNorm - 0.5) * float2(aspect, 1.0)) * 0.9;

    float arrival = frac(master_phase - waveCoord * wave_span + 1.0);
    float actuation = smoothstep(0.02, 0.18, arrival) * (1.0 - smoothstep(0.48, 0.86, arrival));
    actuation = saturate(actuation * (0.55 + master_envelope * 0.75));

    float polarity = step(0.5, hashCell(cellId));
    float2 axis = polarity > 0.5 ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 ortho = float2(-axis.y, axis.x);

    float axisPos = dot(q, axis);
    float orthoPos = dot(q, ortho);
    float openGap = 0.04 + actuation * aperture;
    float plateCenter = 0.26 + openGap * 0.5;
    float plateHalf = max(0.03, 0.24 - openGap * 0.5);

    float upperPlate = boxMask(float2(axisPos, orthoPos - plateCenter), float2(0.45, plateHalf), 0.012);
    float lowerPlate = boxMask(float2(axisPos, orthoPos + plateCenter), float2(0.45, plateHalf), 0.012);
    float plates = max(upperPlate, lowerPlate);

    float frame = max(
        lineSegment(q, float2(-0.48, -0.48), float2(0.48, -0.48), 0.012),
        lineSegment(q, float2(-0.48, 0.48), float2(0.48, 0.48), 0.012));
    frame = max(frame, lineSegment(q, float2(-0.48, -0.48), float2(-0.48, 0.48), 0.012));
    frame = max(frame, lineSegment(q, float2(0.48, -0.48), float2(0.48, 0.48), 0.012));

    float axle = 1.0 - smoothstep(0.045, 0.075, length(q));
    float phaseBand = 1.0 - smoothstep(0.025, 0.075, abs(arrival - 0.12));
    float accent = saturate(phaseBand * (0.35 + master_pulse * 0.9) * accent_gain);

    float3 black = float3(0.004, 0.004, 0.005);
    float3 steel = float3(0.13, 0.135, 0.145);
    float3 white = float3(0.90, 0.91, 0.92);
    float3 warm = float3(0.98, 0.46, 0.12);

    float3 color = black;
    color = lerp(color, steel, plates * 0.64);
    color = lerp(color, white, max(frame * 0.62, plates * (0.25 + 0.55 * (1.0 - actuation))));
    color = lerp(color, warm, saturate(accent * (plates + axle)));
    color = lerp(color, master_play > 0.5 ? warm : steel, axle * 0.25);

    float border = 1.0 - smoothstep(0.001, 0.003, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
    color = lerp(color, white, border * 0.5);

    OutputUAV[DTid.xy] = float4(saturate(color), 1.0);
}
