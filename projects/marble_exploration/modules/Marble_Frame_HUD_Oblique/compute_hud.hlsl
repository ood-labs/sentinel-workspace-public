// frame_hud — procedural radar/porthole frame: concentric bezel rings (some dashed
// + rotating), a tick ring, inner accent ring, and a circular viewport mask.
// Packs float4(hud.rgb, viewportMask) for the two output split passes.

RWTexture2D<float4> OutputUAV : register(u0);

float ringLine(float r, float rr, float w)
{
    return 1.0 - smoothstep(0.0, w, abs(r - rr));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(asp, 1.0) * 2.0;
    float r = length(p);
    float ang = atan2(p.y, p.x);
    const float TAU = 6.2831853;

    // concentric bezel rings clustered around the viewport radius
    float bezel = 0.0;
    [loop]
    for (int i = 0; i < ring_count; i++)
    {
        float f = (float)i / max((float)(ring_count - 1), 1.0);
        float rr = viewport_radius * (0.9 + radius_spread * f);
        float w = 0.0015 + 0.0015 * f;
        float ring = ringLine(r, rr, w);
        float rot = _Time * (rot_speed_a * (1.0 + f)) + f * 3.0;
        float seg = 1.0;
        if ((i % 3) == 1)
            seg = step(0.45, frac((ang + rot) / TAU * (float)(6 + segment_gaps * 2)));
        else if ((i % 3) == 2)
            seg = step(0.15, frac((ang - rot) / TAU * (float)(3 + segment_gaps)));
        bezel = max(bezel, ring * seg);
    }

    // tick ring just outside the viewport
    float rr0 = viewport_radius;
    float ann = smoothstep(rr0 * 1.0, rr0 * 1.015, r) * (1.0 - smoothstep(rr0 * 1.045, rr0 * 1.07, r));
    float tk = step(0.72, frac((ang + _Time * rot_speed_b) / TAU * (float)tick_density));
    float ticks = tk * ann;

    // inner accent ring
    float inner = ringLine(r, viewport_radius * inner_ratio, 0.0015);

    // corner crosshair ticks (screen-space) for HUD chrome
    float corner = 0.0;
    if (corner_ticks != 0)
    {
        float2 e = min(uv, 1.0 - uv);
        float near = min(e.x, e.y);
        float cbar = (1.0 - smoothstep(0.0, 0.001, abs(e.x - 0.04))) * step(e.y, 0.02)
                   + (1.0 - smoothstep(0.0, 0.001, abs(e.y - 0.04))) * step(e.x, 0.02);
        corner = saturate(cbar) * step(near, 0.05);
    }

    float3 col = ring_color * (bezel + inner * 0.7) + accent_color * (ticks + corner);
    col *= intensity;

    // circular viewport mask (1 inside)
    float mask = 1.0 - smoothstep(viewport_radius, viewport_radius * 1.004, r);
    // edge vignette baked into the bezel darkening (kept in hud for additive)
    OutputUAV[pixel] = float4(col, mask);
}
