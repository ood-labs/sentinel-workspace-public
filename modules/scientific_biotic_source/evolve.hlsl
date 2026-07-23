#include "types.hlsli"

StructuredBuffer<float4> ClockState : register(t1);
StructuredBuffer<StimulusRecord> Stimuli : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

float sampleDensity(int2 pixel, int2 fieldSize) {
    int2 limit = max(fieldSize - 1, int2(0, 0));
    return _Tex0.Load(int3(clamp(pixel, int2(0, 0), limit), 0)).r;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    // The organism buffer runs at scale 0.5. _Resolution is the 1280x720
    // pipeline extent, so derive simulation UVs from the actual field texture.
    uint fieldWidth;
    uint fieldHeight;
    _Tex0.GetDimensions(fieldWidth, fieldHeight);
    uint2 fieldSize = uint2(fieldWidth, fieldHeight);
    if (tid.x >= fieldSize.x || tid.y >= fieldSize.y) return;
    int2 pixel = int2(tid.xy);
    float2 uv = ((float2)pixel + 0.5) / float2(fieldSize);
    float aspect = (float)fieldSize.x / max((float)fieldSize.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float loopPhase = frac(ClockState[0].x + phase);

    float seedField = 0.0;
    float vortexField = 0.0;
    float directionField = 0.0;
    [unroll] for (uint i = 0u; i < 16u; ++i) {
        if (!stimulusActive(Stimuli[i])) continue;
        float2 seedP = (Stimuli[i].position - 0.5) * float2(aspect, 1.0);
        float2 d = p - seedP;
        float radius = max(Stimuli[i].radius, 0.015);
        float distanceToSeed = length(d);
        float core = exp(-dot(d, d) / max(radius * radius * 1.8, 1e-5));
        float ring = exp(-pow((distanceToSeed - radius * 1.25) / max(radius * 0.28, 0.006), 2.0));
        float directionWave = sin(dot(d, normalize(Stimuli[i].direction + 1e-4)) * 38.0
                                - loopPhase * 6.2831853 + (float)Stimuli[i].id);
        seedField += core * Stimuli[i].strength * (1.0 - saturate(Stimuli[i].mode));
        vortexField += ring * Stimuli[i].strength * saturate(Stimuli[i].mode);
        directionField += directionWave * core * 0.18;
    }

    int2 fieldSizeInt = int2(fieldSize);
    float previous = sampleDensity(pixel, fieldSizeInt);
    float laplacian = sampleDensity(pixel + int2(1, 0), fieldSizeInt)
                    + sampleDensity(pixel + int2(-1, 0), fieldSizeInt)
                    + sampleDensity(pixel + int2(0, 1), fieldSizeInt)
                    + sampleDensity(pixel + int2(0, -1), fieldSizeInt)
                    - previous * 4.0;

    float latticeA = sin((p.x * 5.7 + p.y * 3.2) * cell_scale + loopPhase * 6.2831853);
    float latticeB = cos((p.y * 7.4 - p.x * 2.1) * cell_scale - loopPhase * 6.2831853);
    float cellular = 0.5 + 0.5 * latticeA * latticeB;
    float analytic = saturate(0.12 + cellular * 0.28 + seedField * seed_gain
                            + vortexField * 0.62 + directionField);
    float relaxation = 1.0 - exp(-max(reaction_rate, 0.01) * min(_DeltaTime, 0.05) * 60.0);
    float density = lerp(previous, analytic, relaxation);
    density = saturate(density + laplacian * diffusion * min(_DeltaTime, 0.05) * 60.0);

    float2 gradient = float2(
        sampleDensity(pixel + int2(1, 0), fieldSizeInt) - sampleDensity(pixel + int2(-1, 0), fieldSizeInt),
        sampleDensity(pixel + int2(0, 1), fieldSizeInt) - sampleDensity(pixel + int2(0, -1), fieldSizeInt)
    );
    OutputUAV[tid.xy] = float4(density, gradient * 0.5 + 0.5, 1.0);
}
