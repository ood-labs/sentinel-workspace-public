#ifndef SENTINEL_SUI_CORE_HLSLI
#define SENTINEL_SUI_CORE_HLSLI

struct SuiContext {
    float2 uv;
    float2 pixel;
    float2 resolution;
    float2 invResolution;
};

SuiContext suiContext(uint2 pixel, float2 resolution) {
    SuiContext c;
    c.resolution = max(resolution, float2(1.0, 1.0));
    c.invResolution = 1.0 / c.resolution;
    c.pixel = float2(pixel) + 0.5;
    c.uv = c.pixel * c.invResolution;
    return c;
}

float4 suiRectInset(SuiContext c, float4 rect, float pixels) {
    float2 d = pixels * c.invResolution;
    return float4(rect.xy + d, rect.zw - d);
}

float4 suiRectOutset(SuiContext c, float4 rect, float pixels) {
    float2 d = pixels * c.invResolution;
    return float4(rect.xy - d, rect.zw + d);
}

float suiSdRectPx(SuiContext c, float4 rect) {
    float2 lo = rect.xy * c.resolution;
    float2 hi = rect.zw * c.resolution;
    float2 center = (lo + hi) * 0.5;
    float2 halfSize = max((hi - lo) * 0.5, 0.0);
    float2 q = abs(c.pixel - center) - halfSize;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float suiCoverage(float signedDistancePx) {
    return 1.0 - smoothstep(-0.65, 0.65, signedDistancePx);
}

float suiFillRect(SuiContext c, float4 rect) {
    return suiCoverage(suiSdRectPx(c, rect));
}

float suiStrokeRect(SuiContext c, float4 rect, float widthPx) {
    float outer = suiFillRect(c, rect);
    float inner = suiFillRect(c, suiRectInset(c, rect, max(widthPx, 0.0)));
    return saturate(outer - inner);
}

float suiSdRoundRectPx(SuiContext c, float4 rect, float radiusPx) {
    float2 lo = rect.xy * c.resolution;
    float2 hi = rect.zw * c.resolution;
    float2 center = (lo + hi) * 0.5;
    float2 halfSize = max((hi - lo) * 0.5, radiusPx.xx);
    float2 q = abs(c.pixel - center) - halfSize + radiusPx;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radiusPx;
}

float suiFillRoundRect(SuiContext c, float4 rect, float radiusPx) {
    return suiCoverage(suiSdRoundRectPx(c, rect, radiusPx));
}

float suiStrokeRoundRect(SuiContext c, float4 rect, float radiusPx, float widthPx) {
    float d = abs(suiSdRoundRectPx(c, rect, radiusPx)) - widthPx * 0.5;
    return suiCoverage(d);
}

float suiLinePx(SuiContext c, float2 aUv, float2 bUv, float widthPx) {
    float2 a = aUv * c.resolution;
    float2 b = bUv * c.resolution;
    float2 ba = b - a;
    float h = saturate(dot(c.pixel - a, ba) / max(dot(ba, ba), 1e-6));
    return suiCoverage(length(c.pixel - (a + ba * h)) - widthPx * 0.5);
}

float suiRingPx(SuiContext c, float2 centerUv, float radiusPx, float widthPx) {
    float d = abs(length(c.pixel - centerUv * c.resolution) - radiusPx) - widthPx * 0.5;
    return suiCoverage(d);
}

float suiDiscPx(SuiContext c, float2 centerUv, float radiusPx) {
    return suiCoverage(length(c.pixel - centerUv * c.resolution) - radiusPx);
}

float suiGridPx(SuiContext c, float spacingPx, float widthPx) {
    float2 d = abs(frac(c.pixel / spacingPx + 0.5) - 0.5) * spacingPx;
    return suiCoverage(min(d.x, d.y) - widthPx * 0.5);
}

float2 suiUvFromDesign(float2 designPixel, float2 designSize) {
    return designPixel / max(designSize, float2(1.0, 1.0));
}

float4 suiRectFromDesign(float4 designRect, float2 designSize) {
    return designRect / float4(designSize, designSize);
}

void suiComposite(inout float3 color, float3 layer, float coverage) {
    color = lerp(color, layer, saturate(coverage));
}

#endif
