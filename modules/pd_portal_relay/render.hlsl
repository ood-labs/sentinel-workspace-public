RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> ProgramInput : register(t0);

struct ParticleRecord
{
    float3 position;
    float age;
    float3 origin;
    float life;
    float2 axis;
    float mass;
    float seed;
    uint kind;
    uint emitterId;
    uint active;
    uint serial;
};

StructuredBuffer<ParticleRecord> ParticleInput : register(t1);

float pdStroke(float d, float width, float aa)
{
    return 1.0 - smoothstep(width, width + aa, abs(d));
}

float pdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float3 pdKindColor(uint kind, float3 liability)
{
    if (kind == 1u) return liability;
    if (kind == 2u) return float3(0.76, 0.80, 0.76);
    return float3(0.32, 0.36, 0.32);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 uv = ((float2)tid.xy + 0.5) / float2((float)width, (float)height);
    float aspect = (float)width / max((float)height, 1.0);
    float aa = 1.2 / max((float)height, 1.0);
    float3 color = ProgramInput.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 liability = liability_color;

    float2 center = float2(0.34, 0.48);
    float2 meanOrigin = 0.0;
    float originWeight = 0.0;
    [loop]
    for (uint i = 0u; i < 192u; ++i)
    {
        ParticleRecord p = ParticleInput[i];
        if (p.active == 0u) continue;
        float w = 0.18 + saturate(p.mass) * 0.82;
        meanOrigin += p.origin.xy * w;
        originWeight += w;
    }
    if (originWeight > 0.001)
    {
        float2 target = float2(0.16 + meanOrigin.x * 0.36, 0.22 + meanOrigin.y * 0.48);
        center = lerp(center, target, portal_drift);
    }

    float2 p = (uv - center) * float2(aspect, 1.0);
    float radial = length(p);
    float portalMask = 1.0 - smoothstep(portal_radius, portal_radius + 0.035, radial);
    float portalEdge = pdStroke(radial - portal_radius, aa * 1.9, aa) + pdStroke(radial - portal_radius * 0.72, aa * 0.65, aa);
    float3 portal = float3(0.006, 0.008, 0.007);
    float spokeLayer = 0.0;
    float3 spokeColor = 0.0;

    [loop]
    for (uint i = 0u; i < 192u; ++i)
    {
        ParticleRecord particle = ParticleInput[i];
        if (particle.active == 0u) continue;

        float depth = saturate(particle.position.z / 4.6);
        float2 origin = (particle.origin.xy - 0.5) * float2(0.70, 0.80);
        float2 current = (particle.position.xy - 0.5) * float2(0.70, 0.80);
        float2 rayStart = float2(0.0, 0.0) + origin * 0.16;
        float2 rayEnd = normalize(current + float2(1e-4, 0.0)) * (0.04 + depth * portal_radius * 0.92);
        float widthMark = lerp(aa * 0.65, aa * 2.4, saturate(particle.mass));
        float spoke = pdStroke(pdSegment(p, rayStart, rayEnd), widthMark, aa);
        float depthRing = pdStroke(abs(radial - (0.06 + depth * portal_radius * 0.78)), aa * 0.62, aa);
        float agePulse = 0.42 + 0.58 * (1.0 - smoothstep(0.0, 0.35, particle.age / max(particle.life, 1e-4)));
        float contribution = saturate(spoke * 0.72 + depthRing * 0.26) * agePulse;
        spokeLayer = max(spokeLayer, contribution);
        spokeColor = max(spokeColor, pdKindColor(particle.kind, liability) * contribution);
    }

    portal += spokeColor * portal_gain;
    portal += liability * portalEdge * (0.62 + 0.25 * sin(_Time * 2.0 + portal_phase * 6.2831853));
    portal += float3(0.42, 0.46, 0.42) * spokeLayer * 0.22;
    color = lerp(color, portal, portalMask * portal_mix);
    color += liability * portalEdge * 0.18;

    // registration cross at the data-centered aperture.
    float cross =
        pdStroke(pdSegment(p, float2(-0.035, 0.0), float2(0.035, 0.0)), aa * 0.72, aa) +
        pdStroke(pdSegment(p, float2(0.0, -0.035), float2(0.0, 0.035)), aa * 0.72, aa);
    color += liability * cross * portalMask * 0.42;
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
