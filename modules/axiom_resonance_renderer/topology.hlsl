RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float segmentPhase(float2 p, float2 a, float2 b)
{
    float2 ba = b - a;
    return saturate(dot(p - a, ba) / max(dot(ba, ba), 1e-6));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / _Resolution.y;
    float routeInk = 0.0;
    float nodeInk = 0.0;
    float vectorInk = 0.0;
    float accentGate = 0.0;

    [loop]
    for (uint i = 0u; i < min(_Data1_Count, 64u); ++i)
    {
        if (_Data1[i].active < 0.5) continue;
        float2 a = (_Data1[i].a - 0.5) * float2(aspect, 1.0);
        float2 b = (_Data1[i].b - 0.5) * float2(aspect, 1.0);
        float d = sdSegment(p, a, b);
        float width = px * lerp(0.45, 1.25, _Data1[i].weight);
        float filament = smoothstep(width * 2.2, width * 0.25, d);
        float along = segmentPhase(p, a, b);
        float dash = smoothstep(0.15, 0.42,
            0.5 + 0.5 * sin((along * 12.0 + _Data1[i].id * 0.37) * 6.2831853));
        float2 tangent = normalize(b - a + float2(1e-6, 0.0));
        float2 normal = float2(-tangent.y, tangent.x);
        float railOffset = px * lerp(2.4, 5.8, _Data1[i].weight);
        float railDistance = min(sdSegment(p, a + normal * railOffset, b + normal * railOffset),
                                 sdSegment(p, a - normal * railOffset, b - normal * railOffset));
        float rails = smoothstep(width * 0.86, width * 0.12, railDistance);
        float routeMark = filament * lerp(0.52, 1.0, dash) + rails * dash * 0.44;
        routeInk = max(routeInk, routeMark * lerp(0.72, 1.0, _Data1[i].weight));
        float groupAccent = step(0.74, frac(_Data1[i].group_id * 0.381966));
        accentGate = max(accentGate, max(filament, rails * dash) * groupAccent * _Data1[i].weight);
    }

    [loop]
    for (uint i = 0u; i < min(_Data0_Count, 64u); ++i)
    {
        if (_Data0[i].active < 0.5) continue;
        float2 center = (_Data0[i].position - 0.5) * float2(aspect, 1.0);
        float2 local = p - center;
        float radius = px * lerp(4.0, 12.0, _Data0[i].weight);
        float ring = smoothstep(px * 0.88, px * 0.12, abs(length(local) - radius));
        float halo = smoothstep(px * 0.66, px * 0.10, abs(length(local) - radius * 1.72));
        float crossX = smoothstep(px * 0.78, px * 0.10, abs(local.y)) * step(abs(local.x), radius * 0.72);
        float crossY = smoothstep(px * 0.78, px * 0.10, abs(local.x)) * step(abs(local.y), radius * 0.72);
        float ticks = step(0.78, 0.5 + 0.5 * cos(atan2(local.y, local.x) * 8.0));
        float haloTicks = halo * ticks;
        nodeInk = max(nodeInk, max(max(ring, haloTicks * 0.54), max(crossX, crossY) * 0.46)
                                * lerp(0.62, 1.0, _Data0[i].weight));

        float2 heading = normalize(_Data0[i].direction * float2(aspect, 1.0));
        float2 arrowEnd = center + heading * (0.025 + _Data0[i].weight * 0.055);
        float arrow = smoothstep(px * 0.88, px * 0.12, sdSegment(p, center, arrowEnd));
        vectorInk = max(vectorInk, arrow * _Data0[i].weight);
        float groupAccent = step(0.74, frac(_Data0[i].group_id * 0.381966)) * step(1.0, _Data0[i].kind);
        accentGate = max(accentGate, ring * groupAccent);
    }

    OutputUAV[tid.xy] = float4(saturate(routeInk), saturate(nodeInk),
                               saturate(vectorInk), saturate(accentGate));
}
