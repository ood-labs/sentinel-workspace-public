// axiom_relief_chamber
// Scaffolded by sentinel_module scaffold_from_ports.
// Visual intent: Dark monochrome rectilinear scientific-instrument ray-marched bas-relief; vermilion only for live kinetic impact pins; localized 3D specimen plate composited over existing program; no mouse controls.

RWTexture2D<float4> OutputUAV : register(u0);

float lineDistance(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-5));
    return length(p - (a + ab * t));
}

float normCoord(float v, float axis) {
    return (abs(v) > 2.0) ? (v / max(axis, 1.0)) : v;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    p -= center_bias * 0.25;

    float3 col = draw_background != 0
        ? lerp(float3(0.015, 0.018, 0.026), float3(0.035, 0.025, 0.055), uv.y)
        : float3(0.0, 0.0, 0.0);

    uint count = min(_Data0_Count, 256);
    float countSignal = saturate((float)count / 8.0);
    col += lerp(palette_a, palette_b, uv.x) * countSignal * 0.18;

    float energy = 0.0;
    float ribbon = 0.0;
    float2 prev = float2(0.0, 0.0);
    bool hasPrev = false;

    for (uint i = 0; i < count; ++i) {
        float2 q = (float2(normCoord(_Data0[i].position.x, _Resolution.x), normCoord(_Data0[i].position.y, _Resolution.y)) - 0.5) * float2(aspect, 1.0);
        float conf = saturate(_Data0[i].position.x);
        float phase = frac(_Time * pulse_speed + (float)i * 0.071);
        float radius = (point_radius / max(_Resolution.y, 1.0)) * (0.75 + 0.75 * phase);

        float d = length(p - q);
        float pointGlow = exp(-d * d / max(radius * radius, 1e-5)) * conf;
        energy += pointGlow;

        if (hasPrev) {
            float ld = lineDistance(p, prev, q);
            ribbon += exp(-ld * 95.0) * conf;
        }
        prev = q;
        hasPrev = true;
    }

    float wave = 0.5 + 0.5 * sin(_Time * 2.4 + energy * field_gain * 6.283);
    float3 dataColor = lerp(palette_a, palette_b, saturate(wave + ribbon * 0.25));

    if (curve_mode == 0) {
        col += dataColor * energy;
    } else if (curve_mode == 1) {
        col += dataColor * max(energy * 0.55, ribbon * 1.4);
    } else {
        float field = sin((p.x + energy * 0.18) * 18.0 + _Time) * cos((p.y - ribbon * 0.12) * 18.0 - _Time);
        col += dataColor * (energy * 0.45 + abs(field) * 0.18 + ribbon);
    }

    if (draw_points == 0) {
        col *= 0.45 + ribbon;
    }

    col = col / (1.0 + col);
    col = pow(saturate(col), 1.0 / 2.2);
    OutputUAV[pixel] = float4(col, 1.0);
}
