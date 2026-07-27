RWTexture2D<float4> OutputUAV : register(u0);

float contourLine(float field, float width)
{
    float d = min(frac(field), 1.0 - frac(field));
    return 1.0 - smoothstep(width, width * 2.0, d);
}

float luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)DTid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float phase = master_phase * 6.2831853;

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float protectedInk = smoothstep(0.10, 0.48, luminance(base));

    float orbitalDeflection = 0.055 * sin(p.x * 4.6 - phase * 0.20);
    orbitalDeflection += 0.025 * sin(p.x * 10.5 + p.y * 2.0 + phase * 0.14);
    float field = (p.y + orbitalDeflection) * (float)field_density + master_envelope * 0.22;
    float sparseField = contourLine(field, 0.0035 + line_weight * 0.0065);

    float phaseWindow = step(0.52, frac(field * 0.5 + 0.1));
    sparseField *= phaseWindow;
    sparseField *= (1.0 - protectedInk * 0.82);

    float faultX = fault_bias + 0.10 * sin(p.y * 5.2 - phase * 0.32);
    float fault = 1.0 - smoothstep(0.0015 + fault_weight * 0.0015, 0.006 + fault_weight * 0.004, abs(p.x - faultX));
    fault *= 0.55 + master_envelope * 0.45;

    float3 white = float3(0.91, 0.92, 0.93);
    float3 warm = float3(0.98, 0.44, 0.11);
    float3 color = base;
    color = lerp(color, white, sparseField * field_opacity);
    color = lerp(color, warm, saturate(fault * fault_opacity + fault * master_pulse * 0.28));

    OutputUAV[DTid.xy] = float4(saturate(color), 1.0);
}
