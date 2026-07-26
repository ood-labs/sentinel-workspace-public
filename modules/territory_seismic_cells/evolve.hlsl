RWTexture2D<float4> OutputUAV : register(u0);

float4 readCell(int2 p, uint width, uint height)
{
    int2 clamped = clamp(p, int2(0, 0), int2((int)width - 1, (int)height - 1));
    return _Tex0.Load(int3(clamped, 0));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint width, height;
    _Tex0.GetDimensions(width, height);
    if (DTid.x >= width || DTid.y >= height) return;

    int2 cell = int2(DTid.xy);
    float4 center = readCell(cell, width, height);
    float previousPhase = center.w;
    float phaseDelta = master_phase - previousPhase;
    phaseDelta -= floor(phaseDelta + 0.5);
    float advance = saturate(abs(phaseDelta) * 240.0);

    if (advance < 1e-5)
    {
        OutputUAV[DTid.xy] = float4(center.xyz, master_phase);
        return;
    }

    float left = readCell(cell + int2(-1, 0), width, height).x;
    float right = readCell(cell + int2(1, 0), width, height).x;
    float up = readCell(cell + int2(0, -1), width, height).x;
    float down = readCell(cell + int2(0, 1), width, height).x;
    float laplacian = left + right + up + down - 4.0 * center.x;

    float2 uv = ((float2)cell + 0.5) / float2(width, height);
    float aspect = (float)width / max((float)height, 1.0);
    float tau = 6.28318530718;
    float2 sourceUv = float2(
        0.5 + 0.285 * sin(master_phase * tau),
        0.5 + 0.235 * sin(master_phase * tau * 1.5 + 1.2));
    float2 delta = (uv - sourceUv) * float2(aspect, 1.0);
    float radius = length(delta);
    float sourceRing = exp(-pow((radius - 0.025) * 95.0, 2.0));
    float sourceCore = exp(-radius * radius * 900.0);
    float injection = (sourceRing - sourceCore * 0.45) * (0.12 + 0.32 * master_envelope);

    float velocity = center.y;
    velocity += laplacian * propagation * advance;
    velocity += injection * advance;
    velocity *= pow(saturate(damping), max(advance, 0.001));

    float heightValue = center.x + velocity * advance;
    heightValue = clamp(heightValue, -2.0, 2.0);
    float activity = lerp(center.z, saturate(abs(velocity) * 4.0 + sourceRing), 0.10 * advance);

    OutputUAV[DTid.xy] = float4(heightValue, velocity, activity, master_phase);
}
