// node_gen — produce glowing-node point records. Optionally snaps points onto
// Field peaks/pits via gradient ascent (input:0 = Field texture).

struct NodeRecord
{
    float2 pos;      // 0..1 screen uv
    float radius;
    float intensity;
    float color_mix; // 0 = white, 1 = orange
    float kind;
    float seed;
    float active;
};

RWStructuredBuffer<NodeRecord> NodesOut : register(u0);

float h11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float sampleH(float2 uv)
{
    return _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).r;
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 128u) return;

    NodeRecord n;
    n.pos = float2(0.5, 0.5);
    n.radius = 0.0; n.intensity = 0.0; n.color_mix = 0.0;
    n.kind = 0.0; n.seed = 0.0; n.active = 0.0;

    if (i >= (uint)node_count) { NodesOut[i] = n; return; }

    float fi = (float)i + (float)seed * 13.0;
    float2 pos = float2(0.5, 0.5) + (float2(h11(fi * 1.7), h11(fi * 3.1)) - 0.5) * 0.9;

    if (placement_mode == 3) // Ring
    {
        float ang = fi * 2.3999632;
        pos = float2(0.5, 0.5) + float2(cos(ang), sin(ang)) * ring_radius * float2(0.5625, 1.0);
    }

    int doPeaks = (placement_mode == 1) ? 1
                : (placement_mode == 2) ? -1
                : (placement_mode == 4 && (frac(fi * 0.5) < 0.5)) ? 1 : 0;
    if (doPeaks != 0)
    {
        [loop]
        for (int k = 0; k < ascent_steps; k++)
        {
            float e = 0.004;
            float gx = sampleH(pos + float2(e, 0)) - sampleH(pos - float2(e, 0));
            float gy = sampleH(pos + float2(0, e)) - sampleH(pos - float2(0, e));
            pos += float2(gx, gy) * ascent_rate * (float)doPeaks;
            pos = clamp(pos, 0.04, 0.96);
        }
    }

    pos += (float2(h11(fi * 5.5), h11(fi * 7.7)) - 0.5) * jitter;
    pos = clamp(pos, 0.03, 0.97);

    n.pos = pos;
    n.radius = lerp(size_min, size_max, h11(fi * 4.2));
    n.color_mix = saturate(color_mix + (h11(fi * 8.8) - 0.5) * 0.6);
    n.kind = (h11(fi * 9.9) < 0.28) ? 1.0 : 0.0;
    n.seed = fi;
    n.intensity = intensity * lerp(0.55, 1.0, h11(fi * 6.1));
    n.active = 1.0;
    NodesOut[i] = n;
}
