RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<float4> ClockState : register(t2);

float sdSegment(float2 p, float2 a, float2 b, out float along)
{
    float2 pa = p - a;
    float2 ba = b - a;
    along = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * along);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 aspectScale = float2(16.0 / 9.0, 1.0);
    float2 p = (uv - 0.5) * aspectScale;
    float phase = ClockState[0].x;

    float2 vectorSum = 0.0;
    float energy = 0.0;
    float occupancy = 0.0;

    [loop]
    for (uint i = 0u; i < 96u; ++i)
    {
        if ((_Data0[i].flags & 1u) == 0u || _Data0[i].confidence < 0.02) continue;
        float2 q = (_Data0[i].position - 0.5) * aspectScale;
        float2 delta = p - q;
        float radius = agent_radius * lerp(0.62, 1.85, saturate(_Data0[i].scale));
        float influence = exp(-dot(delta, delta) / max(radius * radius, 1e-5)) * _Data0[i].confidence;
        float2 radial = normalize(delta + float2(1e-5, 0.0));
        float2 tangent = float2(-radial.y, radial.x);
        float2 measuredMotion = normalize(_Data0[i].velocity * aspectScale + float2(1e-5, 0.0));
        float2 agentDirection = normalize(lerp(tangent, measuredMotion, motion_follow));
        vectorSum += agentDirection * influence * agent_vector_gain;
        energy += influence * (_Data0[i].kind == 0u ? mass_energy : 1.0);
        occupancy = max(occupancy, influence);
    }

    [loop]
    for (uint i = 0u; i < 96u; ++i)
    {
        if ((_Data1[i].flags & 1u) == 0u || _Data1[i].weight < 0.02) continue;
        float2 a = (_Data1[i].a - 0.5) * aspectScale;
        float2 b = (_Data1[i].b - 0.5) * aspectScale;
        float along;
        float distanceToEdge = sdSegment(p, a, b, along);
        float width = edge_radius * lerp(0.55, 1.8, _Data1[i].weight);
        float wireInfluence = exp(-(distanceToEdge * distanceToEdge) / max(width * width, 1e-6));
        float pulse = 0.5 + 0.5 * sin((along * pulse_density - phase * 6.2831853 + _Data1[i].phase * 6.2831853));
        pulse = pow(saturate(pulse), pulse_sharpness);
        float weighted = wireInfluence * _Data1[i].weight;
        vectorSum += normalize(b - a + float2(1e-5, 0.0)) * weighted * edge_vector_gain;
        energy += weighted * lerp(0.35, 1.0, pulse) * pulse_energy;
        occupancy = max(occupancy, weighted);
    }

    float vectorMagnitude = length(vectorSum);
    float2 flow = vectorMagnitude > 1e-5 ? vectorSum / vectorMagnitude : float2(1.0, 0.0);
    energy = 1.0 - exp(-energy * energy_gain);
    occupancy = saturate(occupancy * occupancy_gain);
    OutputUAV[tid.xy] = float4(flow * 0.5 + 0.5, saturate(energy), occupancy);
}
