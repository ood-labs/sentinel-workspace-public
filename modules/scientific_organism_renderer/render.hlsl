RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float sdSegment(float2 p, float2 a, float2 b, out float along)
{
    float2 pa = p - a;
    float2 ba = b - a;
    along = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * along);
}

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 texel = 1.0 / _Resolution.xy;
    float px = 1.0 / _Resolution.y;

    float4 field = _Tex1.SampleLevel(LinearSampler, uv, 0);
    float2 flow = normalize(field.rg * 2.0 - 1.0 + float2(1e-5, 0.0));
    float energy = field.b;
    float occupancy = field.a;
    float2 warpedUv = saturate(uv + flow * energy * warp_amount);

    float3 source = _Tex0.SampleLevel(LinearSampler, warpedUv, 0).rgb;
    float sourceLuma = luminance(source) * source_exposure;
    float lx = luminance(_Tex0.SampleLevel(LinearSampler, saturate(warpedUv + float2(texel.x * 2.0, 0.0)), 0).rgb)
             - luminance(_Tex0.SampleLevel(LinearSampler, saturate(warpedUv - float2(texel.x * 2.0, 0.0)), 0).rgb);
    float ly = luminance(_Tex0.SampleLevel(LinearSampler, saturate(warpedUv + float2(0.0, texel.y * 2.0)), 0).rgb)
             - luminance(_Tex0.SampleLevel(LinearSampler, saturate(warpedUv - float2(0.0, texel.y * 2.0)), 0).rgb);
    float3 normal = normalize(float3(-lx * relief_depth, -ly * relief_depth, 0.28));
    float reliefLight = 0.52 + 0.48 * saturate(dot(normal, normalize(float3(-0.55, -0.35, 0.76))));

    float membrane = 1.0 - smoothstep(0.025, 0.12, abs(frac(sourceLuma * source_bands) - 0.5));
    float sourceBody = smoothstep(source_floor, 1.0, sourceLuma);
    float fieldContour = 1.0 - smoothstep(0.025, 0.10, abs(frac(energy * field_bands) - 0.5));
    float fieldBody = smoothstep(0.03, 0.72, energy);
    float causalSignal = saturate(fieldBody * 0.72 + fieldContour * fieldBody * 0.46);

    float3 col = background_color;
    col += source_color * sourceBody * source_mix * (0.34 + reliefLight * 0.9);
    col += membrane_color * membrane * sourceBody * membrane_mix
         * (0.78 + causalSignal * causal_coupling);
    col += field_color * fieldBody * field_mix;
    col += field_contour_color * fieldContour * fieldBody * field_contour_mix;

    uint edgeLimit = quality_mode == 0 ? 64u : 96u;
    [loop]
    for (uint i = 0u; i < edgeLimit; ++i)
    {
        if ((_Data1[i].flags & 1u) == 0u || _Data1[i].weight < 0.02) continue;
        float2 a = (_Data1[i].a - 0.5) * float2(aspect, 1.0);
        float2 b = (_Data1[i].b - 0.5) * float2(aspect, 1.0);
        float along;
        float d = sdSegment(p, a, b, along);
        float width = px * lerp(0.65, 2.4, saturate(_Data1[i].weight));
        float wire = smoothstep(width * 1.8, width * 0.2, d);
        float dash = step(signal_gap, frac(along * signal_divisions + _Data1[i].phase));
        float pulse = lerp(1.0, dash, signal_articulation);
        float kindGain = _Data1[i].kind == 1u ? 1.35 : (_Data1[i].kind == 2u ? 1.15 : 0.72);
        float3 edgeInk = _Data1[i].kind == 1u ? accent_color : network_color;
        col += edgeInk * wire * _Data1[i].weight * network_mix * pulse * kindGain;
    }

    uint agentLimit = quality_mode == 0 ? 56u : 96u;
    [loop]
    for (uint i = 0u; i < agentLimit; ++i)
    {
        if ((_Data0[i].flags & 1u) == 0u || _Data0[i].confidence < 0.025) continue;
        float2 q = (_Data0[i].position - 0.5) * float2(aspect, 1.0);
        float2 local = p - q;
        float confidence = saturate(_Data0[i].confidence);
        float radius = px * (_Data0[i].kind == 0u ? (7.0 + 52.0 * _Data0[i].scale) : (3.0 + 7.0 * _Data0[i].scale));
        float ring = smoothstep(px * 1.7, px * 0.25, abs(length(local) - radius));
        float core = smoothstep(px * 2.4, px * 0.25, length(local));
        float tick = max(
            smoothstep(px * 1.2, px * 0.2, abs(local.x)) * step(abs(local.y), radius * 0.7),
            smoothstep(px * 1.2, px * 0.2, abs(local.y)) * step(abs(local.x), radius * 0.7)
        );
        float3 agentInk = _Data0[i].kind == 0u ? accent_color : agent_color;
        col += agentInk * confidence * agent_mix * max(ring, max(core * 0.55, tick * 0.35));

        float2 velocityEnd = q + _Data0[i].velocity * float2(aspect, 1.0) * 0.035 * motion_vector_scale;
        float along;
        float velocityLine = smoothstep(px * 1.1, px * 0.2, sdSegment(p, q, velocityEnd, along));
        col += motion_color * velocityLine * confidence * motion_mix;
    }

    // Real confidence telemetry: one discrete slot per agent.
    if (uv.y > 0.944 && uv.y < 0.985)
    {
        uint slot = min((uint)floor(uv.x * 96.0), 95u);
        float cellX = frac(uv.x * 96.0);
        float confidence = saturate(_Data0[slot].confidence);
        float active = ((_Data0[slot].flags & 1u) != 0u) ? 1.0 : 0.0;
        float bar = step(0.13, cellX) * step(cellX, 0.87)
                  * step(uv.y, 0.947 + confidence * 0.034) * active;
        float3 barInk = _Data0[slot].kind == 0u ? accent_color : agent_color;
        col = max(col, barInk * bar * telemetry_mix);
    }

    float minorGrid = smoothstep(0.018, 0.0,
        min(abs(frac(uv.x * 32.0) - 0.5), abs(frac(uv.y * 18.0) - 0.5)));
    float majorGrid = smoothstep(0.025, 0.0,
        min(abs(frac(uv.x * 8.0) - 0.5), abs(frac(uv.y * 4.5) - 0.5)));
    col += grid_color * (minorGrid * minor_grid_mix + majorGrid * major_grid_mix);

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col += frame_color * smoothstep(px * 1.6, px * 0.22, border) * frame_mix;
    float vignette = pow(saturate(1.0 - dot((uv - 0.5) * float2(1.15, 1.0), (uv - 0.5) * float2(1.15, 1.0)) * 2.0), vignette_power);
    col *= lerp(1.0, vignette, vignette_mix);
    col += (hash21((float2)tid.xy) - 0.5) * grain_amount;
    col = pow(max(col, 0.0), 1.0 / max(output_gamma, 0.1));
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
