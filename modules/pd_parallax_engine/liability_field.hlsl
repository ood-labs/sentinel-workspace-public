#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct DebtQuantum
{
    float2 position;
    float2 axis;
    float mass;
    float radius;
    uint kind;
    uint sourceIndex;
    uint ledgerId;
    uint active;
    float phase;
    float age;
};

StructuredBuffer<DebtQuantum> DebtInput : register(t0);

float pdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint targetWidth;
    uint targetHeight;
    OutputUAV.GetDimensions(targetWidth, targetHeight);
    if (tid.x >= targetWidth || tid.y >= targetHeight) return;

    float2 uv = ((float2)tid.xy + 0.5) / max(float2((float)targetWidth, (float)targetHeight), float2(1.0, 1.0));
    float aspect = (float)targetWidth / max((float)targetHeight, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float2 displacement = float2(0.0, 0.0);
    float depth = 0.0;
    float stress = 0.0;
    float phaseValue = frac(phase);

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        DebtQuantum quantum = DebtInput[i];
        if (quantum.active == 0u) continue;

        float2 center = (quantum.position - 0.5) * float2(aspect, 1.0);
        float2 axis = normalize(quantum.axis * float2(1.0, -1.0));
        float2 side = float2(-axis.y, axis.x);
        float localPulse = 0.5 + 0.5 * an_loop_harmonic(
            phaseValue + quantum.phase,
            1.0,
            1.0 + fmod((float)quantum.sourceIndex, 3.0),
            (float)quantum.kind
        );

        if (quantum.kind == 1u)
        {
            float radius = max(0.035, quantum.radius * macro_radius_scale);
            float2 delta = p - center;
            float normalizedDistance = length(delta) / radius;
            float influence = pow(saturate(1.0 - normalizedDistance), 2.0) * quantum.mass;
            float2 outward = length(delta) > 1e-5 ? delta / length(delta) : axis;
            displacement += outward * influence * macro_repulsion;
            depth += influence * macro_depth;
            stress += influence * (0.55 + 0.45 * localPulse);
        }
        else if (quantum.kind == 2u)
        {
            float radius = max(0.02, quantum.radius * hinge_radius_scale);
            float2 delta = p - center;
            float distanceValue = length(delta);
            float influence = pow(saturate(1.0 - distanceValue / (radius * 4.2)), 3.0) * quantum.mass;
            float signedPlane = dot(delta, side);
            float foldSign = signedPlane >= 0.0 ? 1.0 : -1.0;
            displacement += side * foldSign * influence * hinge_fold;
            displacement += axis * sin((phaseValue + quantum.phase) * AN_TAU) * influence * hinge_drift;
            depth += abs(signedPlane) < radius ? influence * hinge_depth : influence * 0.25;
            stress += influence * localPulse;
        }
        else if (quantum.kind == 3u)
        {
            float halfLength = max(0.05, quantum.radius * rail_length_scale);
            float distanceValue = pdSegment(p, center - axis * halfLength, center + axis * halfLength);
            float influence = pow(saturate(1.0 - distanceValue / max(rail_width, 0.001)), 2.0) * quantum.mass;
            displacement += side * influence * rail_shear;
            depth += influence * rail_depth;
            stress += influence;
        }
    }

    displacement = clamp(displacement * field_gain, -0.48, 0.48);
    depth = saturate(depth * field_gain);
    stress = saturate(stress * field_gain);

    OutputUAV[tid.xy] = float4(displacement * 0.5 + 0.5, depth, stress);
}
