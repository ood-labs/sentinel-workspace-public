#include "../_shared/anim/anim.hlsli"

struct ChoreoStats {
    float spring_sample;
    float max_scale;
    float min_scale;
    float inner_scale;
    float outer_scale;
    float scale_variance;
    float anticipation_x;
    float loop_noise_sample;
};

RWStructuredBuffer<ChoreoStats> OutputBuffer : register(u0);

static const int CHOREO_COUNT = 24;
static const int CHOREO_COLS = 6;
static const int CHOREO_ROWS = 4;

float3 springParams()
{
    if (spring_preset == 1) return AN_SMOOTH;
    if (spring_preset == 2) return AN_SNAPPY;
    if (spring_preset == 3) return AN_HEAVY;
    return AN_BOUNCY;
}

float2 instancePos(int i)
{
    int x = i % CHOREO_COLS;
    int y = i / CHOREO_COLS;
    float2 uv = float2((float)x / (float)(CHOREO_COLS - 1), (float)y / (float)(CHOREO_ROWS - 1));
    return (uv - 0.5) * float2(1.32, 0.78);
}

float instanceDelay(float2 p)
{
    float maxR = length(float2(0.66, 0.39));
    return an_stagger_radial(p, float2(0.0, 0.0), 0.75 * stagger_span / max(0.0001, maxR));
}

float instanceScale(int i, float t, float3 params)
{
    float delay = instanceDelay(instancePos(i));
    float localT = max(0.0, t - delay);
    if (localT <= 0.0001) return 0.0;
    return max(0.0, an_spring(localT, params.x, params.y, params.z));
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float3 params = springParams();
    ChoreoStats s;
    s.spring_sample = an_spring(spring_t, params.x, params.y, params.z);
    s.max_scale = 0.0;
    s.min_scale = 999.0;
    s.inner_scale = 0.0;
    s.outer_scale = 0.0;
    s.scale_variance = 0.0;
    s.anticipation_x = -0.45 + travel * an_anticipate(saturate(demo_time / max(0.0001, anticipation_duration)), anticipation_bias);
    s.loop_noise_sample = an_loop_noise(demo_time, loop_period, 1.0, 3.0);

    float sum = 0.0;
    float innerMax = 0.0;
    float outerMax = 0.0;
    for (int i = 0; i < CHOREO_COUNT; ++i) {
        float2 p = instancePos(i);
        float scale = instanceScale(i, demo_time, params);
        float r = length(p);
        innerMax = r < 0.28 ? max(innerMax, scale) : innerMax;
        outerMax = r > 0.66 ? max(outerMax, scale) : outerMax;
        s.max_scale = max(s.max_scale, scale);
        s.min_scale = min(s.min_scale, scale);
        sum += scale;
    }

    float mean = sum / (float)CHOREO_COUNT;
    float variance = 0.0;
    for (int j = 0; j < CHOREO_COUNT; ++j) {
        float d = instanceScale(j, demo_time, params) - mean;
        variance += d * d;
    }

    s.inner_scale = innerMax;
    s.outer_scale = outerMax;
    s.scale_variance = variance / (float)CHOREO_COUNT;
    OutputBuffer[0] = s;
}
