RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 flow = 0.0;
    float nodeDensity = 0.0;
    float routeDensity = 0.0;
    float gestureEnergy = 0.0;

    [loop]
    for (uint i = 0u; i < min(_Data0_Count, 64u); ++i)
    {
        if (_Data0[i].active < 0.5) continue;
        float2 center = (_Data0[i].position - 0.5) * float2(aspect, 1.0);
        float2 delta = p - center;
        float radius = feature_radius * lerp(0.72, 1.65, _Data0[i].weight);
        float falloff = exp(-dot(delta, delta) / max(radius * radius, 1e-5));
        float2 heading = normalize(_Data0[i].direction * float2(aspect, 1.0));
        float groupSign = frac(_Data0[i].group_id * 0.381966) > 0.5 ? 1.0 : -1.0;
        float2 tangent = float2(-delta.y, delta.x) * groupSign;
        flow += (heading * 0.74 + tangent * 2.1) * falloff * _Data0[i].weight * field_gain;
        nodeDensity += falloff * _Data0[i].weight;
    }

    [loop]
    for (uint i = 0u; i < min(_Data1_Count, 64u); ++i)
    {
        if (_Data1[i].active < 0.5) continue;
        float2 a = (_Data1[i].a - 0.5) * float2(aspect, 1.0);
        float2 b = (_Data1[i].b - 0.5) * float2(aspect, 1.0);
        float distanceToRoute = sdSegment(p, a, b);
        float routeFalloff = exp(-distanceToRoute * distanceToRoute / max(feature_radius * feature_radius * 0.32, 1e-5));
        float2 routeDirection = normalize(b - a + 1e-5);
        flow += routeDirection * routeFalloff * _Data1[i].weight * route_tension;
        routeDensity += routeFalloff * _Data1[i].weight;
    }

    [loop]
    for (uint i = 0u; i < min(_Data2_Count, 3u); ++i)
    {
        if (_Data2[i].active < 0.5) continue;
        float2 center = (_Data2[i].position - 0.5) * float2(aspect, 1.0);
        float2 delta = p - center;
        float radius = max(_Data2[i].radius, 0.015);
        float falloff = exp(-dot(delta, delta) / max(radius * radius, 1e-5));
        float2 radial = normalize(delta + float2(1e-5, 0.0));
        float2 authoredDirection = normalize(_Data2[i].direction * float2(aspect, 1.0) + 1e-5);
        float mode = _Data2[i].mode;
        float2 gestureFlow = mode < 0.5 ? -radial :
                             (mode < 1.5 ? authoredDirection : radial);
        flow += gestureFlow * abs(_Data2[i].strength) * falloff * gesture_gain;
        gestureEnergy += falloff * abs(_Data2[i].strength);
    }

    flow = tanh(flow * 0.34);
    float topology = saturate(nodeDensity * 0.28 + routeDensity * 0.52);
    float gesture = saturate(gestureEnergy * 0.48);
    OutputUAV[tid.xy] = float4(flow * 0.5 + 0.5, topology, gesture);
}
