RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= 64u) return;

    if (i >= _Data0_Count || _Data0[i].active < 0.5)
    {
        OutputUAV[uint2(i, 0)] = 0.0;
        return;
    }

    float2 current = saturate(_Data0[i].position);
    float bestDistance = 1e6;
    float4 bestState = 0.0;

    [unroll]
    for (uint j = 0u; j < 64u; ++j)
    {
        float4 candidate = _Tex1.Load(int3(j, 0, 0));
        float valid = step(1e-5, dot(candidate.xy, candidate.xy))
                    * step(max(candidate.x, candidate.y), 1.001);
        float distanceToCurrent = length(current - candidate.xy);
        if (valid > 0.5 && distanceToCurrent < bestDistance)
        {
            bestDistance = distanceToCurrent;
            bestState = candidate;
        }
    }

    float matched = step(bestDistance, matching_radius);
    float2 measuredVelocity = (current - bestState.xy) * matched;
    float2 velocity = lerp(bestState.zw, measuredVelocity, velocity_smoothing) * matched;
    OutputUAV[uint2(i, 0)] = float4(current, velocity);
}
