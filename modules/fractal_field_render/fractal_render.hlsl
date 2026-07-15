struct FractalSeed {
    float4 orbit;
    float4 color;
    float4 rule;
    float4 warp;
};

StructuredBuffer<FractalSeed> Seeds : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

#define PI 3.14159265359
#define TWO_PI 6.28318530718

float2 rot(float2 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float3 tonemap(float3 x)
{
    return x / (1.0 + x);
}

float3 hueShift(float3 c, float h)
{
    float3 k = float3(0.57735, 0.57735, 0.57735);
    float ca = cos(h);
    float sa = sin(h);
    return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 2.0;
    p = (p - designer_center) / max(zoom, 0.001);

    float t = _Time;
    int iter = clamp(iterations, 2, 14);
    int seedLimit = min((int)_Data0_Count, 64);
    float3 col = float3(0.0, 0.0, 0.0);
    float orbitGlow = 0.0;
    float lineInk = 0.0;
    float trap = 1000.0;

    float2 q0 = rot(p, t * 0.03 * motion);
    float2 q = q0;
    float kalei = max(1.0, (float)kaleidoscope);
    float wedge = atan2(q.y, q.x);
    float rad = length(q);
    wedge = abs(frac(wedge / TWO_PI * kalei + 0.5) - 0.5) * TWO_PI / kalei;
    q = float2(cos(wedge), sin(wedge)) * rad;

    [loop]
    for (int sidx = 0; sidx < seedLimit; ++sidx)
    {
        FractalSeed s = Seeds[sidx];
        if (s.rule.w < 0.5) continue;

        float2 z = q - s.orbit.xy * morph;
        float localTrap = 99.0;
        float phase = s.warp.x + t * motion * s.warp.y;
        float2 drift = float2(cos(phase), sin(phase)) * 0.06 * morph;
        float power = max(1.1, s.rule.x + fractal_power);

        [loop]
        for (int j = 0; j < 14; ++j)
        {
            if (j >= iter) break;
            z = abs(z);
            z = rot(z, s.orbit.w * 0.08 + phase * 0.07 + (float)j * 0.19);
            z = z / max(dot(z, z), 0.085 + fold * 0.08);
            z = z * (0.53 + 0.055 * power) - (s.orbit.xy + drift) * (0.72 + fold * 0.11);
            localTrap = min(localTrap, abs(length(z) - s.orbit.z * (1.5 + 0.2 * sin(phase))));
        }

        float vein = exp(-localTrap * line_density);
        float bloom = max(0.0, 1.0 - localTrap * (7.0 + glow * 12.0));
        float idHue = s.warp.w * 0.07 + palette_spin + t * 0.02 * motion;
        float3 sc = hueShift(s.color.rgb, idHue);
        col += sc * (vein * 0.11 + bloom * bloom * glow * 0.34);
        lineInk += vein * 0.035;
        orbitGlow += bloom * 0.018;
        trap = min(trap, localTrap);
    }

    float rings = 0.5 + 0.5 * sin((length(q0) * 9.0 - t * motion) * TWO_PI + trap * 18.0);
    float grid = pow(abs(sin((q0.x + q0.y) * 16.0 + t * 0.7)), 24.0);
    float vignette = smoothstep(1.6, 0.15, length((uv - 0.5) * float2(aspect, 1.0)));
    float3 bg = lerp(float3(0.010, 0.012, 0.020), float3(0.035, 0.012, 0.045), uv.y);
    bg += float3(0.015, 0.035, 0.055) * rings * orbitGlow;
    bg += float3(0.04, 0.12, 0.18) * grid * circuit;

    col = col * intensity + bg;
    col += float3(0.7, 0.9, 1.0) * lineInk * circuit;
    col = tonemap(col * (1.0 + orbitGlow * 7.0));
    col = pow(saturate(col), 1.0 / 2.2);
    col *= 0.55 + 0.45 * vignette;

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
