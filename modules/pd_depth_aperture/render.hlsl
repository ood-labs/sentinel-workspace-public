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

float pdHash(float x)
{
    return frac(sin(x * 12.9898 + 78.233) * 43758.5453);
}

float pdDepthSlice(float depth, float center)
{
    return 1.0 - smoothstep(slice_spread, slice_spread + 0.06, abs(depth - center));
}

float3 pdKindColor(uint kind, float3 liability)
{
    if (kind == 1u) return liability;
    if (kind == 2u) return float3(0.74, 0.78, 0.73);
    return float3(0.34, 0.38, 0.34);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 uv = ((float2)tid.xy + 0.5) / float2((float)width, (float)height);
    float aa = 1.25 / max((float)height, 1.0);
    float3 color = ProgramInput.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 liability = liability_color;
    float3 graphite = float3(0.18, 0.20, 0.18);

    float dockLeft = 1.0 - sideband_width;
    float inDock = step(dockLeft, uv.x);
    float2 q = float2((uv.x - dockLeft) / max(sideband_width, 1e-4), uv.y);
    float dockFade = smoothstep(dockLeft - 0.02, dockLeft + 0.01, uv.x);

    // Preserve the full Program as the main image, then turn only the right
    // sideband into a live depth instrument.
    float3 aperture = float3(0.004, 0.006, 0.005);
    float rail = 0.0;
    float pulse = 0.5 + 0.5 * sin(_Time * pulse_rate * 6.2831853);

    [unroll]
    for (uint band = 0u; band < 3u; ++band)
    {
        float bandY = 0.18 + (float)band * 0.32;
        float2 bandCenter = float2(0.5, bandY);
        float box = step(abs(q.x - 0.5), 0.44) * step(abs(q.y - bandY), 0.115);
        float railLine = pdStroke(q.y - bandY, aa * 0.7, aa) * rail_gain;
        float bracket =
            pdStroke(q.x - 0.055, aa * 0.7, aa) +
            pdStroke(q.x - 0.945, aa * 0.7, aa) +
            pdStroke(q.y - (bandY - 0.115), aa * 0.7, aa) +
            pdStroke(q.y - (bandY + 0.115), aa * 0.7, aa);
        rail = max(rail, (railLine + bracket * 0.42) * box);

        float sliceCenter = (float)band * 0.5;
        [loop]
        for (uint i = 0u; i < 192u; ++i)
        {
            ParticleRecord particle = ParticleInput[i];
            if (particle.active == 0u) continue;

            float depth = saturate(particle.position.z / 4.6);
            float slice = pdDepthSlice(depth, sliceCenter);
            if (slice <= 0.001) continue;

            float2 origin = float2(
                0.20 + frac(particle.origin.x * 1.37 + particle.seed * 0.19) * 0.60,
                bandY + (particle.origin.y - 0.5) * 0.16
            );
            float2 live = origin + float2(
                (particle.position.x - particle.origin.x) * 0.55,
                (particle.position.y - particle.origin.y) * 0.20
            );
            float ageNorm = saturate(particle.age / max(particle.life, 1e-4));
            float markSize = lerp(0.006, 0.019, saturate(particle.mass)) * (1.0 - depth * 0.38);
            float mark = 0.0;
            if (particle.kind == 1u)
            {
                mark = pdStroke(length(q - live) - markSize, aa * 0.75, aa) * 1.25;
            }
            else
            {
                float2 axis = normalize(particle.axis + float2(1e-4, 0.0));
                float2 a = live - axis * markSize * 2.2;
                float2 b = live + axis * markSize * 2.2;
                mark = pdStroke(pdSegment(q, a, b), max(aa * 0.55, markSize * 0.14), aa);
            }

            float tether = pdStroke(pdSegment(q, origin, live), max(aa * 0.38, markSize * 0.08), aa);
            float birth = 1.0 - smoothstep(0.0, 0.22, ageNorm);
            float event = saturate(mark + tether * (0.24 + birth * 0.55));
            float3 ink = pdKindColor(particle.kind, liability) * event * slice * event_gain;
            aperture += ink;
        }
    }

    // Second representation: the same records become a depth rosette. Every
    // ribbon passes through one shared aperture center and its radius encodes
    // live depth, so the sideband reads a spatial instrument rather than a HUD.
    [loop]
    for (uint i = 0u; i < 192u; ++i)
    {
        ParticleRecord particle = ParticleInput[i];
        if (particle.active == 0u) continue;

        float depth = saturate(particle.position.z / 4.6);
        float ageNorm = saturate(particle.age / max(particle.life, 1e-4));
        float2 lensCenter = float2(0.5, 0.5);
        float2 originVector = normalize(particle.origin.xy - 0.5 + float2(1e-4, 0.0));
        float originAngle = atan2(originVector.y, originVector.x);
        float angle = originAngle + (particle.seed - 0.5) * 0.32 + ageNorm * 0.18;
        float2 radialDirection = float2(cos(angle), sin(angle));
        float2 laneStart = lensCenter + originVector * 0.045;
        float2 livePoint = lensCenter + radialDirection * (0.08 + depth * 0.39);
        livePoint += (particle.position.xy - particle.origin.xy) * 0.06;
        float liveX = livePoint.x;
        float ribbonWidth = lerp(0.0022, 0.0062, saturate(particle.mass));
        float ribbon = pdStroke(pdSegment(q, laneStart, livePoint), ribbonWidth, aa);
        float tip = pdStroke(length(q - livePoint), ribbonWidth * 2.2, aa);
        float pulseTip = tip * (0.42 + 0.58 * (0.5 + 0.5 * sin(_Time * pulse_rate * 6.2831853 + particle.seed * 9.0)));

        if (particle.kind == 1u)
        {
            float halo = pdStroke(abs(length(q - livePoint) - ribbonWidth * 3.4), aa * 0.7, aa);
            aperture += liability * (ribbon * 0.55 + pulseTip + halo * 0.30) * event_gain;
        }
        else if (particle.kind == 2u)
        {
            float tick = pdStroke(abs(q.x - liveX), ribbonWidth * 0.72, aa)
                * step(0.08, q.y) * step(q.y, 0.92);
            aperture += float3(0.72, 0.76, 0.72) * (ribbon * 0.42 + tick * 0.22 + pulseTip * 0.35) * event_gain;
        }
        else
        {
            float beam = pdStroke(pdSegment(q, laneStart, livePoint), ribbonWidth * 1.65, aa);
            aperture += float3(0.34, 0.38, 0.34) * (beam + pulseTip * 0.28) * event_gain;
        }
    }

    float vertical = pdStroke(q.x - 0.5, aa * 0.5, aa) * 0.42;
    float header = step(abs(q.y - 0.045), 0.012) * step(0.04, q.x) * step(q.x, 0.96);
    aperture += graphite * (rail + vertical) * 0.20;
    aperture += liability * header * (0.35 + pulse * 0.35);
    aperture += liability * rail * 0.28;

    color = lerp(color, aperture, inDock * aperture_mix * dockFade);
    color += liability * vertical * inDock * 0.06;
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
