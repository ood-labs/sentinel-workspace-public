struct KineticEvent
{
    float2 position;
    float2 velocity;
    float speed;
    float energy;
    float active;
    float id;
};

StructuredBuffer<KineticEvent> Events : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

float hash11(float p)
{
    return frac(sin(p * 127.1 + 311.7) * 43758.5453123);
}

float ringMark(float2 p, float radius, float thickness)
{
    return smoothstep(thickness, thickness * 0.16, abs(length(p) - radius));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float waveInk = 0.0;
    float particleInk = 0.0;
    float streakInk = 0.0;

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        KineticEvent e = Events[i];
        if (e.active < 0.5 || e.energy < 0.001) continue;

        float2 center = (e.position - 0.5) * float2(aspect, 1.0);
        float2 local = p - center;
        float speedBoost = 0.72 + e.energy * 0.78;
        float basePhase = phase * emission_rate + hash11(e.id + 0.37);

        [unroll]
        for (int w = 0; w < 4; ++w)
        {
            if (w >= wave_count) break;
            float age = frac(basePhase + (float)w / max((float)wave_count, 1.0));
            float radius = age * wave_reach * speedBoost;
            float fade = (1.0 - age) * e.energy;
            waveInk = max(waveInk, ringMark(local, radius, wave_thickness) * fade);
        }

        float2 velocityDirection = length(e.velocity) > 1e-5
                                 ? normalize(e.velocity * float2(aspect, 1.0))
                                 : float2(1.0, 0.0);
        float2 velocityNormal = float2(-velocityDirection.y, velocityDirection.x);
        [unroll]
        for (int k = 0; k < 6; ++k)
        {
            if (k >= particle_count) break;
            float seed = e.id * 13.17 + (float)k * 7.91;
            float age = frac(basePhase * 1.31 + hash11(seed));
            float spread = (hash11(seed + 2.7) * 2.0 - 1.0);
            float2 direction = normalize(velocityDirection + velocityNormal * spread * 1.35);
            float reach = particle_reach * age * speedBoost * lerp(0.55, 1.25, hash11(seed + 8.1));
            float2 particlePosition = center + direction * reach;
            float particleDistance = length(p - particlePosition);
            float particle = smoothstep(particle_size * 1.8, particle_size * 0.18, particleDistance);
            particleInk = max(particleInk, particle * (1.0 - age) * e.energy);
        }

        float2 tail = center - velocityDirection * particle_reach * e.energy * 0.32;
        float2 segment = center - tail;
        float t = saturate(dot(p - tail, segment) / max(dot(segment, segment), 1e-6));
        float streakDistance = length((p - tail) - segment * t);
        streakInk = max(streakInk,
                        smoothstep(wave_thickness * 1.4, wave_thickness * 0.18, streakDistance)
                        * e.energy * (1.0 - t));
    }

    float3 current = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float waveLayer = saturate((waveInk + streakInk * 0.42) * emission_gain);
    float splinterLayer = saturate(particleInk * emission_gain);
    float3 col = max(current, paper_color * waveLayer * 0.82);
    col = lerp(col, accent_color, splinterLayer * 0.92);
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
