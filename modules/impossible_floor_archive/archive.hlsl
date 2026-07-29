RWTexture2D<float4> OutputUAV : register(u0);

float arc_hash(float2 p) {
    p = frac(p * float2(0.1271, 0.3117));
    p += dot(p, p.yx + 17.17);
    return frac(p.x * p.y * 19.19);
}

float arc_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

float card_mask(float2 p, float2 lo, float2 hi) {
    float inside = step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
    float edge = min(min(abs(p.x-lo.x), abs(hi.x-p.x)), min(abs(p.y-lo.y), abs(hi.y-p.y)));
    return inside * smoothstep(0.004, 0.0, edge);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = uv;
    float horizon = floor_y;
    float floorMask = smoothstep(horizon - 0.008, horizon + 0.015, p.y);
    float floorT = saturate((p.y - horizon) / max(floor_height, 0.01));
    float fold = (p.x - 0.5) * fold_angle * (0.5 + floorT);
    float2 deckUv = float2(frac(p.x + fold + archive_phase * card_rate * 0.16),
                           saturate(0.55 + floorT * 0.48));
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 deck = _Tex0.SampleLevel(LinearSampler, deckUv, 0).rgb;
    float3 col = lerp(base, deck * 0.72 + paper_color * 0.10, floorMask * archive_mix);

    // A grounded conveyor of four moving source-derived cards creates a new
    // orthographic miniature world under the observatory.
    float2 local = float2(p.x, floorT);
    float moving = archive_phase * card_rate;
    float cardW = 0.17;
    for (int i = 0; i < 4; ++i) {
        float fx = frac((float)i * 0.285 + moving * (1.0 + (float)i * 0.11));
        float2 lo = float2(fx - cardW * 0.5, 0.12 + 0.15 * (i % 2));
        float2 hi = lo + float2(cardW, 0.56 - 0.08 * (i % 2));
        float m = card_mask(local, lo, hi) * floorMask;
        float2 cardUv = float2(frac((local.x - lo.x) / cardW + 0.13 * i + moving * 0.08),
                               saturate((local.y - lo.y) / max(hi.y - lo.y, 0.001)));
        float3 cardSource = _Tex0.SampleLevel(LinearSampler, cardUv, 0).rgb;
        float3 card = lerp(paper_color, cardSource, 0.68);
        float paperShade = 0.72 + 0.20 * sin(cardUv.x * 15.0 + i * 1.7 + archive_phase * 6.28);
        col = lerp(col, card * paperShade, m * archive_mix);
        float border = card_mask(local, lo - 0.006, hi + 0.006) - m;
        col = lerp(col, line_color, saturate(border) * archive_gain);

        float ticks = arc_line(cardUv.x * 17.0 + archive_phase * card_rate, 0.026) *
                      smoothstep(0.98, 0.30, cardUv.y);
        col = lerp(col, paper_color, ticks * m * archive_gain * 0.68);
    }

    float gridX = arc_line((p.x + moving * 0.11) * 22.0, 0.017);
    float gridY = arc_line((floorT - archive_phase * card_rate * 0.12) * 12.0, 0.014);
    float grid = max(gridX, gridY) * floorMask;
    float rail = smoothstep(0.009, 0.0, abs(p.y - horizon)) +
                 smoothstep(0.009, 0.0, abs(p.y - (horizon + floor_height * 0.52)));
    col = lerp(col, line_color, saturate(grid * 0.42 + rail) * archive_gain * archive_mix);

    float route = smoothstep(0.010, 0.0, abs(p.y - (horizon + 0.08 + sin(p.x * 8.0 + archive_phase * 6.28) * 0.035))) * floorMask;
    col = lerp(col, paper_color, route * archive_gain * 0.55);

    float noise = arc_hash((float2)tid.xy + archive_phase * 41.0) - 0.5;
    col += noise * 0.009 * floorMask * archive_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
