#ifndef SENTINEL_SUI_LAYOUT_HLSLI
#define SENTINEL_SUI_LAYOUT_HLSLI

static const uint SUI_LAYOUT_ROW = 0u;
static const uint SUI_LAYOUT_COLUMN = 1u;

// Approved Scientific UI spacing defaults, in output pixels.
static const float SUI_OUTER_PADDING_PX = 15.0;
static const float SUI_SECTION_GAP_PX = 10.595863;
static const float SUI_CONTROL_HEIGHT_PX = 32.0;
static const float SUI_CONTROL_GAP_PX = 6.446163;

struct SuiLayout {
    float4 bounds;
    float2 cursor;
    float gap;
    uint direction;
};

float4 suiInsetNormalized(SuiContext c, float4 rect, float pixels) {
    return suiRectInset(c, rect, pixels);
}

float4 suiSplitLeft(float4 rect, float fraction, float gapNormalized) {
    float split = lerp(rect.x, rect.z, saturate(fraction));
    return float4(rect.x, rect.y, split - gapNormalized * 0.5, rect.w);
}

float4 suiSplitRight(float4 rect, float fraction, float gapNormalized) {
    float split = lerp(rect.x, rect.z, saturate(fraction));
    return float4(split + gapNormalized * 0.5, rect.y, rect.z, rect.w);
}

SuiLayout suiLayout(float4 bounds, uint direction, float gapNormalized) {
    SuiLayout l;
    l.bounds = bounds;
    l.cursor = bounds.xy;
    l.gap = gapNormalized;
    l.direction = direction;
    return l;
}

float4 suiLayoutNext(inout SuiLayout l, float extentNormalized) {
    float4 rect;
    if (l.direction == SUI_LAYOUT_ROW) {
        rect = float4(l.cursor.x, l.bounds.y, min(l.cursor.x + extentNormalized, l.bounds.z), l.bounds.w);
        l.cursor.x = rect.z + l.gap;
    } else {
        rect = float4(l.bounds.x, l.cursor.y, l.bounds.z, min(l.cursor.y + extentNormalized, l.bounds.w));
        l.cursor.y = rect.w + l.gap;
    }
    return rect;
}

#endif
