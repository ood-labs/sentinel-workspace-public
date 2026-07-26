RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;

    float4 ctrl = _Tex3.Load(int3(0, 0, 0));
    float lastGeneration = _Tex0.Load(int3(0, 1, 0)).a;
    bool freshQueue = ctrl.g != lastGeneration;

    float3 pressureTex = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;
    float2 direction = pressureTex.gb - 0.5;
    float2 advectedUv = saturate(uv - direction * advection * _DeltaTime);
    float4 previous = _Tex0.SampleLevel(LinearSampler, advectedUv, 0);

    float decay = pow(saturate(retention), _DeltaTime * 60.0);
    float energy = previous.r * decay;
    float age = saturate(previous.g + _DeltaTime * age_rate);
    float scar = previous.b * pow(saturate(scar_retention), _DeltaTime * 60.0);

    float3 program = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float live = smoothstep(deposit_threshold, 1.0, luminance(program));
    float pressure = pressureTex.r;
    energy += live * deposition_gain * _DeltaTime * 60.0;
    energy += pressure * pressure_deposition * _DeltaTime * 60.0;
    scar = max(scar, live * pressure * scar_gain);
    age = lerp(age, 0.0, saturate(live * 0.12));

    if (freshQueue)
    {
        float aspect = _Resolution.x / _Resolution.y;
        [unroll]
        for (uint s = 0u; s < 8u; ++s)
        {
            float4 q = _Tex3.Load(int3(1 + (int)s, 0, 0));
            if (q.w != ctrl.g) continue;
            if (q.z < -4.0)
            {
                energy = 0.0;
                age = 1.0;
                scar = 0.0;
                continue;
            }
            if (abs(q.z) > 0.001)
            {
                float2 d = (uv - q.xy) * float2(aspect, 1.0);
                float r = ctrl.r * 0.42;
                float brush = exp(-dot(d, d) / max(r * r, 1e-5));
                if (q.z > 0.0)
                {
                    energy += brush * q.z * gesture_gain;
                    scar = max(scar, brush * q.z);
                    age = lerp(age, 0.0, brush);
                }
                else
                {
                    energy *= 1.0 - brush * erase_gain;
                    scar *= 1.0 - brush * erase_gain;
                }
            }
        }
    }

    if (tid.x == 0u && tid.y == 1u)
    {
        OutputUAV[tid.xy] = float4(0.0, 1.0, 0.0, ctrl.g);
        return;
    }

    OutputUAV[tid.xy] = float4(min(energy, 6.0), age, saturate(scar), ctrl.g);
}
