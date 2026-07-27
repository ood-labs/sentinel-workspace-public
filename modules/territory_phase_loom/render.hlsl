RWTexture2D<float4> OutputUAV : register(u0);

float stroke(float distanceValue, float width)
{
    return 1.0 - smoothstep(width, width * 1.8, abs(distanceValue));
}

float segmentDistance(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float tau = 6.28318530718;
    float phase = master_phase * tau;
    float px = 1.0 / max(_Resolution.y, 1.0);

    float3 warm = accent;
    float3 neutral = float3(0.84, 0.86, 0.82);
    float3 dim = float3(0.20, 0.215, 0.205);
    float3 col = float3(0.0045, 0.005, 0.0045);

    float frameX = 0.5 * aspect - 0.055;
    float frameY = 0.445;
    float frame = stroke(abs(p.x) - frameX, px * 0.8) * step(abs(p.y), frameY);
    frame += stroke(abs(p.y) - frameY, px * 0.8) * step(abs(p.x), frameX);
    col += dim * saturate(frame);

    float horizontal = 0.0;
    float vertical = 0.0;
    float crossingWarm = 0.0;
    float activeBand = floor(master_phase * max((float)thread_count, 1.0));
    float width = px * lerp(0.72, 1.45, line_weight);

    [loop]
    for (int i = 0; i < 48; ++i)
    {
        if (i >= thread_count) break;
        float fi = (float)i;
        float row = (fi + 0.5) / max((float)thread_count, 1.0);
        float baseY = lerp(-0.39, 0.39, row);
        float stagger = fi * 0.37;
        float warp = sin(p.x * (3.0 + tension) + phase + stagger);
        warp += 0.45 * sin(p.x * 7.0 - phase * 1.7 + stagger * 0.6);
        float yCurve = baseY + warp * curvature * (0.010 + 0.022 * master_envelope);
        float d = p.y - yCurve;
        float threadMask = stroke(d, width);
        float parity = fmod(fi, 2.0);
        horizontal = max(horizontal, threadMask * lerp(0.50, 0.92, parity));

        float activeDistance = min(abs(fi - activeBand), (float)thread_count - abs(fi - activeBand));
        crossingWarm = max(crossingWarm, threadMask * (1.0 - step(1.15, activeDistance)));
    }

    int verticalCount = max(8, thread_count * 2 / 3);
    [loop]
    for (int j = 0; j < 32; ++j)
    {
        if (j >= verticalCount) break;
        float fj = (float)j;
        float column = (fj + 0.5) / max((float)verticalCount, 1.0);
        float baseX = lerp(-frameX + 0.035, frameX - 0.035, column);
        float stagger = fj * 0.51;
        float warp = sin(p.y * (7.0 + tension) - phase * 1.23 + stagger);
        warp += 0.35 * sin(p.y * 15.0 + phase * 0.7 - stagger * 0.4);
        float xCurve = baseX + warp * curvature * (0.009 + 0.018 * (1.0 - master_envelope));
        float d = p.x - xCurve;
        float threadMask = stroke(d, width * 0.92);
        float gate = 0.58 + 0.42 * step(0.0, sin((p.y * 22.0) + stagger + phase));
        vertical = max(vertical, threadMask * gate);
    }

    col += neutral * saturate(horizontal * 0.82 + vertical * 0.64);
    col = lerp(col, warm, saturate(crossingWarm * (0.74 + 0.26 * master_pulse)));

    float scanX = lerp(-frameX, frameX, master_phase);
    float scan = stroke(p.x - scanX, px * 0.75) * step(abs(p.y), frameY);
    col = lerp(col, warm, scan * 0.85);

    float corner = 0.0;
    float tickLen = 0.032;
    corner += stroke(segmentDistance(p, float2(-frameX, -frameY), float2(-frameX + tickLen, -frameY)), px);
    corner += stroke(segmentDistance(p, float2(-frameX, -frameY), float2(-frameX, -frameY + tickLen)), px);
    corner += stroke(segmentDistance(p, float2(frameX, frameY), float2(frameX - tickLen, frameY)), px);
    corner += stroke(segmentDistance(p, float2(frameX, frameY), float2(frameX, frameY - tickLen)), px);
    col += neutral * saturate(corner);

    float vignette = saturate(1.0 - 0.22 * dot(p / float2(max(frameX, 0.1), frameY), p / float2(max(frameX, 0.1), frameY)));
    col *= vignette;
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
