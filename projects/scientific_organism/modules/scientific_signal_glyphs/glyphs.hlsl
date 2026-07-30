RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float rectangleOutline(float2 p, float2 lo, float2 hi, float width)
{
    float2 center = (lo + hi) * 0.5;
    float2 halfSize = max((hi - lo) * 0.5, width);
    float2 d = abs(p - center) - halfSize;
    float outside = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    return smoothstep(width * 1.6, width * 0.25, abs(outside));
}

float stableIdBits(float2 uv, float2 origin, uint stableId, float2 pixelSize)
{
    float2 local = (uv - origin) / pixelSize;
    if (local.y < 0.0 || local.y > 3.0 || local.x < 0.0 || local.x >= 30.0) return 0.0;
    uint bitIndex = min((uint)floor(local.x / 3.0), 9u);
    float cellX = frac(local.x / 3.0);
    float active = (stableId & (1u << bitIndex)) != 0u ? 1.0 : 0.0;
    return active * step(0.18, cellX) * step(cellX, 0.82) * step(0.2, local.y) * step(local.y, 2.8);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 pixelSize = 1.0 / _Resolution.xy;
    float px = 1.0 / _Resolution.y;
    float markPx = px * glyph_scale;
    float2 markPixelSize = pixelSize * glyph_scale;
    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 overlay = 0.0;

    [loop]
    for (uint i = 0u; i < 96u; ++i)
    {
        if ((_Data0[i].flags & 1u) == 0u || _Data0[i].confidence < glyph_floor) continue;
        float confidence = saturate(_Data0[i].confidence);
        float2 q = (_Data0[i].position - 0.5) * float2(aspect, 1.0);
        float2 local = p - q;

        if (_Data0[i].kind == 0u)
        {
            float2 lo = (_Data0[i].aux.xy - 0.5) * float2(aspect, 1.0);
            float2 hi = (_Data0[i].aux.zw - 0.5) * float2(aspect, 1.0);
            float bounds = rectangleOutline(p, lo, hi, markPx);
            float2 size = hi - lo;
            float tickLength = min(0.035, min(size.x, size.y) * 0.22);
            float ticks = 0.0;
            ticks = max(ticks, smoothstep(markPx * 1.5, markPx * 0.2, sdSegment(p, lo, lo + float2(tickLength, 0.0))));
            ticks = max(ticks, smoothstep(markPx * 1.5, markPx * 0.2, sdSegment(p, lo, lo + float2(0.0, tickLength))));
            ticks = max(ticks, smoothstep(markPx * 1.5, markPx * 0.2, sdSegment(p, hi, hi - float2(tickLength, 0.0))));
            ticks = max(ticks, smoothstep(markPx * 1.5, markPx * 0.2, sdSegment(p, hi, hi - float2(0.0, tickLength))));
            float bits = stableIdBits(uv, _Data0[i].aux.xy + float2(0.0, -8.0 * markPixelSize.y), _Data0[i].stable_id, markPixelSize);
            overlay += mass_glyph_color * confidence * (bounds * bounds_mix + ticks * tick_mix + bits * id_mix);
        }
        else if (_Data0[i].kind == 1u)
        {
            float2 direction = float2(cos(_Data0[i].angle), sin(_Data0[i].angle));
            float2 a = q - direction * markPx * (3.0 + _Data0[i].scale * 7.0);
            float2 b = q + direction * markPx * (5.0 + _Data0[i].scale * 10.0);
            float orientation = smoothstep(markPx * 1.4, markPx * 0.2, sdSegment(p, a, b));
            float responseRing = smoothstep(markPx * 1.4, markPx * 0.2,
                abs(length(local) - markPx * (4.0 + confidence * 5.0)));
            overlay += corner_glyph_color * confidence * (orientation * orientation_mix + responseRing * corner_ring_mix);
        }
        else
        {
            float2 a = (_Data0[i].aux.xy - 0.5) * float2(aspect, 1.0);
            float2 b = (_Data0[i].aux.zw - 0.5) * float2(aspect, 1.0);
            float observed = smoothstep(markPx * 1.5, markPx * 0.2, sdSegment(p, a, b));
            float endpoints = smoothstep(markPx * 2.2, markPx * 0.2, min(length(p - a), length(p - b)));
            overlay += line_glyph_color * confidence * (observed * observed_line_mix + endpoints * endpoint_mix);
        }
    }

    [loop]
    for (uint i = 0u; i < 96u; ++i)
    {
        if ((_Data1[i].flags & 1u) == 0u || _Data1[i].weight < glyph_floor) continue;
        float2 probeUv = lerp(_Data1[i].a, _Data1[i].b, _Data1[i].phase);
        float2 probe = (probeUv - 0.5) * float2(aspect, 1.0);
        float marker = smoothstep(markPx * 1.5, markPx * 0.2, abs(length(p - probe) - markPx * (2.0 + _Data1[i].tension * 3.0)));
        overlay += phase_probe_color * marker * _Data1[i].weight * phase_probe_mix;
    }

    OutputUAV[tid.xy] = float4(saturate(col + overlay * glyph_mix), 1.0);
}
