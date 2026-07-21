#include "../_shared/ui/sui_theme.hlsli"
#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

StructuredBuffer<float4> PaintState : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

static const float2 PC_CANVAS_PIXELS = float2(1080.0, 1350.0);
static const float PC_TOOLBAR_PX = 32.0;

float4 pcClearRect(float2 resolution)
{
    float2 safeResolution = max(resolution, float2(1.0, 1.0));
    return float4((safeResolution.x - 68.0) / safeResolution.x, 5.0 / safeResolution.y,
                  (safeResolution.x - 8.0) / safeResolution.x, 27.0 / safeResolution.y);
}

float pcFitScale(float2 resolution)
{
    float availableHeight = max(resolution.y - PC_TOOLBAR_PX, 1.0);
    return max(min(resolution.x / PC_CANVAS_PIXELS.x, availableHeight / PC_CANVAS_PIXELS.y), 0.0001);
}

float2 pcScreenToCanvas(float2 screenUv, float2 resolution, float2 viewPan, float viewZoom)
{
    float availableHeight = max(resolution.y - PC_TOOLBAR_PX, 1.0);
    float2 centerPx = float2(resolution.x * 0.5, PC_TOOLBAR_PX + availableHeight * 0.5);
    return (screenUv * resolution - centerPx) / (PC_CANVAS_PIXELS * pcFitScale(resolution) * max(viewZoom, 0.01)) + 0.5 + viewPan;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;
    float2 resolution = float2(width, height);
    SuiContext c = suiContext(id.xy, resolution);
    SuiTheme theme = suiMonochromeTheme();
    float4 view = PaintState[19];
    float2 canvasUv = pcScreenToCanvas(c.uv, resolution, view.xy, view.z);

    float checker = fmod(floor(id.x / 18.0) + floor(id.y / 18.0), 2.0);
    float3 color = lerp(float3(0.055, 0.060, 0.066), float3(0.075, 0.081, 0.089), checker);
    bool inside = all(canvasUv >= 0.0) && all(canvasUv <= 1.0) && id.y >= (uint)PC_TOOLBAR_PX;
    if (inside) color = _Tex0.SampleLevel(LinearSampler, canvasUv, 0).rgb;

    float toolbarY = PC_TOOLBAR_PX / resolution.y;
    suiComposite(color, float3(0.010, 0.010, 0.012), suiFillRect(c, float4(0.0, 0.0, 1.0, toolbarY)));
    suiComposite(color, theme.text, suiLabelText(c, float2(10.0, 8.0) / resolution, suiTextStyle(0.82, 0.16), UI_LABEL_TITLE));
    suiComposite(color, theme.muted, suiLabelText(c, float2(145.0, 9.0) / resolution, suiTextStyle(0.60, 0.0), UI_LABEL_NAV));
    float4 clearRect = pcClearRect(resolution);
    suiComposite(color, theme.control, suiFillRect(c, clearRect));
    suiComposite(color, theme.border, suiStrokeRect(c, clearRect, 1.0));
    suiComposite(color, theme.text, suiLabelText(c, clearRect.xy + float2(12.0, 6.0) / resolution, suiTextStyle(0.62, 0.0), UI_LABEL_CLEAR));

    if (inside) {
        float2 pointerCanvas = pcScreenToCanvas(_ViewportPointerPosition, resolution, view.xy, view.z);
        float2 d = (canvasUv - pointerCanvas) * float2(0.8, 1.0);
        // Match the inverse texture transform used by poster_update.hlsl.
        float a = radians(-rotation);
        d = mul(float2x2(cos(a), -sin(a), sin(a), cos(a)), d);
        d.x /= max(brush_aspect, 0.05);
        float effectiveBrushSize = PaintState[0].y;
        float ring = abs(length(d) - effectiveBrushSize * 0.5);
        float pixelCanvas = 1.0 / max(PC_CANVAS_PIXELS.y * pcFitScale(resolution) * view.z, 1.0);
        float cursor = smoothstep(pixelCanvas * 2.2, pixelCanvas * 0.55, ring);
        color = lerp(color, 1.0 - color, cursor * 0.88);
    }
    OutputUAV[id.xy] = float4(saturate(color), 1.0);
}
