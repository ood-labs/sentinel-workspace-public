RWTexture2D<float4> OutputUAV : register(u0);

static const int MAX_RECORDS = 8;

float rectMask(float2 px, float2 center, float2 halfSize)
{
    float2 d = abs(px - center) - halfSize;
    float outside = length(max(d, 0.0));
    float inside = min(max(d.x, d.y), 0.0);
    return smoothstep(1.5, 0.0, outside + inside);
}

float lineMask(float distPx, float widthPx)
{
    return smoothstep(widthPx, 0.0, abs(distPx));
}

float3 cueColor(float colorId)
{
    float h = frac(colorId * 0.23 + 0.55);
    float3 p = abs(frac(h + float3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0);
    return lerp(float3(1.0, 1.0, 1.0), saturate(p - 1.0), 0.72);
}

float maxTimelineEnd()
{
    float endTime = 1.0;
    uint count = min(_Data0_Count, (uint)MAX_RECORDS);
    for (uint i = 0; i < count; ++i) {
        endTime = max(endTime, _Data0[i].start + _Data0[i].duration);
    }
    return endTime;
}

float maxTrackIndex()
{
    float track = 0.0;
    uint count = min(_Data0_Count, (uint)MAX_RECORDS);
    for (uint i = 0; i < count; ++i) {
        track = max(track, _Data0[i].track);
    }
    return track;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 px = (float2)pixel + 0.5;
    float W = _Resolution.x;
    float H = _Resolution.y;
    float left = 78.0;
    float right = W - 28.0;
    float top = 28.0;
    float bottom = H - 30.0;
    float trackCount = max(1.0, maxTrackIndex() + 1.0);
    float rowGap = 8.0;
    float rowH = max(20.0, (bottom - top - rowGap * (trackCount - 1.0)) / trackCount);
    float span = max(max(1.0, timeline_span), maxTimelineEnd());
    float timelineW = max(1.0, right - left);

    float3 col = float3(0.028, 0.032, 0.036);

    float panel = rectMask(px, float2(W * 0.5, H * 0.5), float2(W * 0.5 - 12.0, H * 0.5 - 12.0));
    col = lerp(col, float3(0.045, 0.050, 0.058), panel * 0.8);

    for (int row = 0; row < 8; ++row) {
        if ((float)row >= trackCount) break;
        float y0 = top + (float)row * (rowH + rowGap);
        float y1 = y0 + rowH;
        float yc = (y0 + y1) * 0.5;
        float rowMask = rectMask(px, float2((left + right) * 0.5, yc), float2(timelineW * 0.5, rowH * 0.5));
        float shade = (row % 2 == 0) ? 0.060 : 0.052;
        col = lerp(col, float3(shade, shade + 0.006, shade + 0.014), rowMask);
        col += float3(0.06, 0.07, 0.08) * lineMask(px.y - y0, 0.8) * step(left, px.x) * step(px.x, right);
        col += float3(0.06, 0.07, 0.08) * lineMask(px.y - y1, 0.8) * step(left, px.x) * step(px.x, right);
    }

    for (int grid = 0; grid <= 12; ++grid) {
        float x = left + timelineW * ((float)grid / 12.0);
        float major = (grid % 4 == 0) ? 1.0 : 0.35;
        col += float3(0.08, 0.09, 0.10) * lineMask(px.x - x, 0.7) * major * step(top, px.y) * step(px.y, bottom);
    }

    uint count = min(_Data0_Count, (uint)MAX_RECORDS);
    for (uint i = 0; i < count; ++i) {
        float track = clamp(_Data0[i].track, 0.0, 7.0);
        float start = _Data0[i].start;
        float duration = max(0.001, _Data0[i].duration);
        float x0 = left + saturate(start / span) * timelineW;
        float x1 = left + saturate((start + duration) / span) * timelineW;
        float y0 = top + track * (rowH + rowGap) + 6.0;
        float y1 = y0 + rowH - 12.0;
        float2 center = float2((x0 + x1) * 0.5, (y0 + y1) * 0.5);
        float2 halfSize = float2(max(3.0, (x1 - x0) * 0.5 - 2.0), max(3.0, (y1 - y0) * 0.5));
        float block = rectMask(px, center, halfSize);
        float active = saturate(_Data0[i].state * 0.5);
        float3 c = cueColor(_Data0[i].color_id);
        col = lerp(col, c * (0.45 + 0.35 * active), block);
        float edge = lineMask(px.x - x0, 1.4) + lineMask(px.x - x1, 1.4);
        col += c * edge * step(y0, px.y) * step(px.y, y1) * 0.5;
    }

    float playX = left + saturate(playhead_seconds / span) * timelineW;
    float play = lineMask(px.x - playX, 2.2) * step(top - 10.0, px.y) * step(px.y, bottom + 10.0);
    col = lerp(col, float3(1.0, 0.96, 0.74), play);
    col += float3(1.0, 0.78, 0.30) * lineMask(px.x - playX, 7.0) * 0.18;

    float leftRail = lineMask(px.x - left, 1.0) * step(top, px.y) * step(px.y, bottom);
    float bottomRail = lineMask(px.y - bottom, 1.0) * step(left, px.x) * step(px.x, right);
    col += float3(0.14, 0.16, 0.18) * (leftRail + bottomRail);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
