#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

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

float circleMask(float2 p, float radius)
{
    return smoothstep(radius, radius - 0.006, length(p));
}

float3 palette(float i)
{
    return 0.55 + 0.45 * cos(float3(0.0, 2.1, 4.2) + i * 0.41);
}

float3 renderWavefront(float2 p)
{
    float3 params = springParams();
    float life = saturate(cue_a_life);
    float3 col = float3(0.014, 0.016, 0.018);

    float grid = 0.0;
    float2 g = abs(frac((p + 1.0) * float2(8.0, 5.0)) - 0.5);
    grid = 1.0 - smoothstep(0.47, 0.5, min(g.x, g.y));
    col += grid * float3(0.018, 0.022, 0.026) * (0.3 + 0.7 * life);

    for (int i = 0; i < CHOREO_COUNT; ++i) {
        float2 center = instancePos(i);
        float scale = instanceScale(i, demo_time, params) * life;
        float radius = base_radius * scale;
        float m = circleMask(p - center, radius);
        float ring = smoothstep(radius + 0.008, radius, length(p - center))
            * smoothstep(radius - 0.018, radius - 0.006, length(p - center));
        float3 c = palette((float)i);
        col = lerp(col, c, m * saturate(scale));
        col += c * ring * saturate(scale - 1.0) * 1.7;
    }

    return col;
}

float beatPulse()
{
    float tight = saturate(tightness_macro);
    float phase = saturate(beat_phase);
    float decay = lerp(1.25, 7.5, tight);
    return pow(1.0 - phase, decay);
}

float3 renderCueB(float2 p)
{
    float rawLife = saturate(cue_b_life);
    float life = rawLife * rawLife * (3.0 - 2.0 * rawLife);
    float pulse = beatPulse();
    float diag = abs(frac((p.x * 2.2 + p.y * 1.5) + beat_phase) - 0.5);
    float stripe = smoothstep(0.22, 0.0, diag);
    float sweep = smoothstep(0.055 + pulse * 0.035, 0.0, abs(length(p * float2(0.72, 1.15)) - (0.38 + 0.18 * life)));
    float2 orbit = p - float2(cos(beat_phase * AN_TAU) * 0.34, sin(beat_phase * AN_TAU) * 0.18);
    float orb = smoothstep(0.12 + 0.04 * pulse, 0.0, length(orbit));
    float3 col = float3(0.018, 0.012, 0.028);
    col += stripe * float3(0.13, 0.08, 0.20);
    col += sweep * float3(0.08, 0.62, 0.88);
    col += orb * float3(0.98, 0.16, 0.58) * (0.72 + pulse);
    col += pulse * float3(0.03, 0.12, 0.18);
    return col * life;
}

float anticipationX(float t)
{
    float u = an_anticipate(saturate(t / max(0.0001, anticipation_duration)), anticipation_bias);
    return -0.45 + travel * u;
}

float3 renderAnticipation(float2 p)
{
    float x = anticipationX(demo_time);
    float2 center = float2(x, 0.0);
    float guide = smoothstep(0.006, 0.0, abs(p.y + 0.25)) * smoothstep(0.55, 0.0, abs(p.x));
    float startMark = smoothstep(0.012, 0.0, abs(p.x + 0.45)) * smoothstep(0.32, 0.0, abs(p.y));
    float endMark = smoothstep(0.012, 0.0, abs(p.x - (-0.45 + travel))) * smoothstep(0.32, 0.0, abs(p.y));
    float body = circleMask(p - center, 0.07);
    float glow = smoothstep(0.24, 0.03, length(p - center));
    float backZone = smoothstep(0.10, 0.0, abs(p.y - 0.18)) * (1.0 - smoothstep(-0.45, -0.28, p.x));
    float3 col = float3(0.018, 0.016, 0.018);
    col += guide * float3(0.08, 0.08, 0.075);
    col += startMark * float3(0.75, 0.28, 0.12);
    col += endMark * float3(0.08, 0.55, 0.85);
    col += backZone * float3(0.28, 0.07, 0.04);
    col += glow * float3(0.04, 0.12, 0.16);
    col = lerp(col, float3(1.0, 0.35, 0.08), body);
    return col;
}

float3 renderLoopNoise(float2 p)
{
    float3 col = float3(0.012, 0.016, 0.019);
    float ringBase = 0.34;
    float angle = atan2(p.y, p.x);
    float radial = length(p);
    for (int i = 0; i < 18; ++i) {
        float fi = (float)i;
        float a = fi / 18.0 * AN_TAU;
        float noise = an_loop_noise(demo_time + fi * 0.11, loop_period, 1.0, fi + 2.0);
        float2 dir = float2(cos(a), sin(a));
        float2 center = dir * (ringBase + (noise - 0.5) * 0.22);
        float m = circleMask(p - center, 0.035 + noise * 0.035);
        col = lerp(col, palette(fi + 3.0), m);
    }
    float ringLine = smoothstep(0.006, 0.0, abs(radial - ringBase));
    col += ringLine * float3(0.06, 0.07, 0.08);
    float loopPhase = frac(demo_time / max(0.0001, loop_period)) * AN_TAU;
    col += 0.03 * (0.5 + 0.5 * cos(angle * 6.0 + loopPhase));
    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(1.0, _Resolution.y);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 2.0;

    float3 col;
    if (demo_mode > 0.5 && demo_mode < 1.5) {
        col = renderAnticipation(p);
    } else if (demo_mode >= 1.5) {
        col = renderLoopNoise(p);
    } else {
        col = renderWavefront(p);
    }

    float rawBLife = saturate(cue_b_life);
    float bLife = rawBLife * rawBLife * (3.0 - 2.0 * rawBLife);
    float3 cueB = renderCueB(p);
    col = col * (1.0 - 0.32 * bLife) + cueB;
    col += beatPulse() * float3(0.015, 0.04, 0.07);

    float vignette = smoothstep(1.15, 0.25, length(p * float2(0.75, 1.0)));
    col *= 0.68 + 0.32 * vignette;
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
