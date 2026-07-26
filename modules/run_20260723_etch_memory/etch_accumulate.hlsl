RWTexture2D<float4> OutputUAV : register(u0);

float4 em_sample_current(float2 uv)
{
    float2 safeUv = saturate(uv);
    int2 coord = int2(safeUv * max(_Resolution.xy - 1.0, float2(1.0, 1.0)));
    return _Tex0.Load(int3(coord, 0));
}

float4 em_sample_memory(float2 uv)
{
    float2 safeUv = saturate(uv);
    int2 coord = int2(safeUv * max(_Resolution.xy - 1.0, float2(1.0, 1.0)));
    return _Tex1.Load(int3(coord, 0));
}

float2 em_rotate(float2 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 center = memory_anchor;
    float2 p = (uv - center) * float2(aspect, 1.0);

    float phaseAngle = sin(scan_phase * 6.2831853) * 0.00045 * rotational_drag;
    float2 previousP = em_rotate(p, phaseAngle);
    float row = floor(uv.y * 13.0 + scan_phase * 3.0);
    float rowSign = ((int)row & 1) == 0 ? -1.0 : 1.0;
    previousP.x -= rowSign * directional_drag * 0.00024;
    previousP.y += sin(p.x * 5.0 + scan_phase * 6.2831853) * directional_drag * 0.00016;
    float2 previousUv = center + previousP / float2(aspect, 1.0);

    float4 current = em_sample_current(uv);
    float4 previous = em_sample_memory(previousUv);
    float dtFrames = max(_DeltaTime, 0.0001) * 60.0;
    float decay = pow(saturate(memory_decay), dtFrames);
    float3 retained = previous.rgb * decay;

    float currentLuma = dot(current.rgb, float3(0.2126, 0.7152, 0.0722));
    float retainGate = smoothstep(etch_threshold - 0.12, etch_threshold + 0.12, currentLuma);
    float3 etchedInput = current.rgb * lerp(present_floor, 1.0, retainGate);

    float3 maximumMemory = max(retained, etchedInput * injection);
    float additiveGain = 0.025 + additive_memory * 0.11;
    float3 boundedAdditive = saturate(retained + etchedInput * injection * additiveGain);
    float3 memory = lerp(maximumMemory, boundedAdditive, additive_memory * 0.55);
    memory = min(memory, 1.0);

    float hot = saturate(current.r - max(current.g, current.b) * 1.12);
    float3 hotEtch = accent_memory_color * hot * accent_persistence;
    memory = max(memory, hotEtch);

    float scanBand = abs(frac(uv.y * scan_density + scan_phase) - 0.5) * 2.0;
    float scanCut = smoothstep(0.0, 0.2, scanBand);
    memory *= lerp(1.0 - scan_depth, 1.0, scanCut);

    if (clear_memory != 0)
    {
        memory = current.rgb;
    }

    OutputUAV[pixel] = float4(saturate(memory), 1.0);
}
