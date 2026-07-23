// Five-dimensional cut-and-project sampler. Each thread decodes one point
// from {-1,0,1}^5, projects it into physical/perpendicular space, and applies
// a decagonal acceptance window. The resulting records drive the 3D lane.
struct QuasiRecord {
    float3 position;
    float scale;
    float phase;
    float family;
    float hue;
    float active;
    float3 normal;
    float pad;
};

RWStructuredBuffer<QuasiRecord> QuasiOut : register(u0);

float2 dir5(int i, float harmonic)
{
    float a = 6.28318530718 * ((float)i / 5.0) * harmonic;
    return float2(cos(a), sin(a));
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint idx = DTid.x;
    if (idx >= 243u) return;

    uint code = idx;
    float2 physical = 0.0;
    float2 internalP = 0.0;
    float sumN = 0.0;
    float family = 0.0;
    [unroll]
    for (int k = 0; k < 5; ++k) {
        int digit = (int)(code % 3u) - 1;
        code /= 3u;
        float n = (float)digit;
        physical += n * dir5(k, 1.0);
        internalP += n * dir5(k, 2.0);
        sumN += n;
        family += abs(n) * (float)(k + 1);
    }

    float phi = 1.61803398875;
    float windowD = length(internalP + phason_shift * float2(cos(phase * 6.283), sin(phase * 6.283)));
    float accept = 1.0 - smoothstep(window_radius, window_radius + window_softness, windowD);

    QuasiRecord q;
    float2 p = physical * lattice_scale / phi;
    float lift = lift_amount * (sin(dot(p, float2(2.7, 4.37)) + phase * 6.2831853)
                 + sin(dot(p, float2(-4.37, 2.7)) - phase * 12.5663706)) * 0.5;
    q.position = float3(p.x, lift + sumN * layer_spacing, p.y);
    q.scale = point_scale * lerp(0.55, 1.35, frac(family * 0.6180339));
    q.phase = frac(family * 0.137 + windowD * 0.31);
    q.family = fmod(family, 5.0);
    q.hue = frac(hue_offset + q.family * 0.118 + q.phase * 0.15);
    q.active = (accept > acceptance_cut && idx != 121u) ? 1.0 : 0.0;
    q.normal = normalize(float3(-lift * 0.18, 1.0, lift * 0.12));
    q.pad = 0.0;
    QuasiOut[idx] = q;
}
