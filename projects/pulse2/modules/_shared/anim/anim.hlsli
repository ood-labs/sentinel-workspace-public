#ifndef SENTINEL_ANIM_HLSLI
#define SENTINEL_ANIM_HLSLI

// Sentinel motion vocabulary.
//
// Phase accumulator rule: any timeline with a live-variable rate must integrate
// phase into persistent state, for example phase += rate * dt. Do not multiply a
// live rate by absolute time, because changing the rate would retroactively
// rescale history and pop the animation.

static const float AN_PI = 3.14159265358979323846;
static const float AN_TAU = 6.28318530717958647692;

static const float3 AN_BOUNCY = float3(1.0, 70.0, 6.0);
static const float3 AN_SNAPPY = float3(1.0, 95.0, 12.0);
static const float3 AN_SMOOTH = float3(1.0, 50.0, 16.0);
static const float3 AN_HEAVY = float3(1.6, 42.0, 18.0);

float an_spring_v(float t, float x0, float v0, float m, float k, float c)
{
    t = max(0.0, t);
    m = max(m, 0.0001);
    k = max(k, 0.0001);
    c = max(c, 0.0);

    float target = 1.0;
    float y0 = x0 - target;
    float w0 = sqrt(k / m);
    float zeta = c / (2.0 * sqrt(k * m));
    float y;

    if (zeta < 0.9999) {
        float wd = w0 * sqrt(max(0.0, 1.0 - zeta * zeta));
        float a = y0;
        float b = (v0 + zeta * w0 * y0) / max(wd, 0.0001);
        y = exp(-zeta * w0 * t) * (a * cos(wd * t) + b * sin(wd * t));
    } else if (zeta <= 1.0001) {
        float a = y0;
        float b = v0 + w0 * y0;
        y = (a + b * t) * exp(-w0 * t);
    } else {
        float root = sqrt(max(0.0, zeta * zeta - 1.0));
        float r1 = -w0 * (zeta - root);
        float r2 = -w0 * (zeta + root);
        float denom = abs(r1 - r2) < 0.0001 ? 0.0001 : (r1 - r2);
        float a = (v0 - r2 * y0) / denom;
        float b = y0 - a;
        y = a * exp(r1 * t) + b * exp(r2 * t);
    }

    return target + y;
}

float an_spring(float t, float m, float k, float c)
{
    return an_spring_v(t, 0.0, 0.0, m, k, c);
}

float an_stagger_index(float i, float n, float span)
{
    float denom = max(1.0, n - 1.0);
    return saturate(i / denom) * max(0.0, span);
}

float an_stagger_radial(float2 p, float2 origin, float scale)
{
    return length(p - origin) * max(0.0, scale);
}

float an_stagger_wave(float2 p, float2 dir, float scale)
{
    float2 n = normalize(abs(dir.x) + abs(dir.y) < 0.0001 ? float2(1.0, 0.0) : dir);
    return max(0.0, dot(p, n)) * max(0.0, scale);
}

float an_hash31(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

float an_stagger_noise(float2 p, float freq, float scale, float seed)
{
    float h = an_hash31(float3(floor(p * max(0.0001, freq)), seed));
    return h * max(0.0, scale);
}

float an_anticipate(float t, float bias)
{
    t = saturate(t);
    return t * t * ((bias + 1.0) * t - bias);
}

float2 an_squash(float vel_approx, float gamma)
{
    float x = 1.0 + max(0.0, vel_approx) * max(0.0, gamma);
    return float2(x, rcp(max(0.0001, x)));
}

float an_loop_noise(float t, float period, float radius, float seed)
{
    period = max(period, 0.0001);
    float phase = frac(t / period) * AN_TAU;
    float n = sin(phase + seed * 12.9898)
        + 0.5 * sin(2.0 * phase + seed * 4.1414)
        + 0.25 * cos(3.0 * phase + seed * 2.7183);
    float normalized = n / 1.75 * 0.5 + 0.5;
    return saturate(0.5 + (normalized - 0.5) * max(0.0, radius));
}

float an_loop_harmonic(float t, float period, float harmonic, float phase)
{
    period = max(period, 0.0001);
    return sin(frac(t / period) * AN_TAU * max(1.0, harmonic) + phase);
}

#endif
