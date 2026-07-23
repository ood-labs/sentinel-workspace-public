static const float TWO_PI = 6.28318530718;

float lineGrid(float2 p, float density) {
    float2 cell = abs(frac(p * density + 0.5) - 0.5) / max(fwidth(p * density), 1e-4);
    return 1.0 - saturate(min(cell.x, cell.y));
}

float tunnelRings(float radius) {
    float rings = 0.0;
    [unroll] for (int i = 0; i < 7; ++i) {
        float travel = frac((float)i / 7.0 + _Time * spawn_rate * 0.20);
        float ringRadius = lerp(0.035, 1.55, travel * travel);
        float thickness = lerp(0.0015, 0.006, travel);
        float ring = 1.0 - smoothstep(thickness, thickness * 2.2, abs(radius - ringRadius));
        rings += ring * travel * travel * (1.0 - smoothstep(1.25, 1.55, ringRadius));
    }
    return saturate(rings);
}

float4 main(VS_OUTPUT input) : SV_TARGET0 {
    float2 uv = input.Uv;
    float2 p = uv * 2.0 - 1.0;
    p.x *= _Resolution.x / max(_Resolution.y, 1.0);
    float radius = length(p);
    float angle = atan2(p.y, p.x) / TWO_PI + 0.5;

    float3 background = float3(0.0015, 0.0017, 0.0021);
    uint mode = (uint)clamp(scene_mode, 0, 2);
    if (mode == 0u) {
        float rings = tunnelRings(radius);
        float radialCell = abs(frac(angle * 40.0 + 0.5) - 0.5);
        float streak = smoothstep(0.475, 0.50, radialCell) * smoothstep(0.18, 1.25, radius);
        float centerMist = exp(-radius * 4.2);
        background += stage_glow * (rings * 0.022 + streak * 0.005 + centerMist * 0.008);
    } else if (mode == 1u) {
        float horizon = 0.59;
        background += exp(-radius * 2.8) * stage_glow * 0.010;
        if (uv.y > horizon) {
            float depth = 1.0 / max(uv.y - horizon, 0.012);
            float2 floorUv = float2((uv.x - 0.5) * depth * 0.22, depth * 0.07 + _Time * spawn_rate * 0.25);
            float grid = lineGrid(floorUv, grid_density * 0.10);
            float fade = saturate((uv.y - horizon) * 2.7) * exp(-depth * 0.020);
            background += grid * fade * stage_glow * 0.050;
        }
    } else {
        float halo = exp(-abs(radius - 0.54) * 42.0) + exp(-abs(radius - 0.92) * 65.0) * 0.45;
        float spokes = smoothstep(0.482, 0.50, abs(frac(angle * 24.0) - 0.5));
        background += stage_glow * (halo * 0.032 + spokes * smoothstep(0.35, 1.2, radius) * 0.006);
    }

    float4 scene = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float alpha = saturate(scene.a);
    float3 color = lerp(background, scene.rgb, alpha);
    color += scene.rgb * alpha * stage_glow * 0.025;
    float vignetteMask = smoothstep(1.40, 0.30, length(p * float2(0.72, 1.0)));
    color *= lerp(1.0, vignetteMask, saturate(vignette));
    color = color / (1.0 + color);
    color = pow(max(color, 0.0), 1.0 / 2.2);
    return float4(saturate(color), 1.0);
}
