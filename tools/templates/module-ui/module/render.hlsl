#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_controls.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "../_shared/ui/sui3_theme.hlsli"
#include "_ui.generated.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float4 uiPixels(float4 normalizedRect, float2 resolution) {
    return normalizedRect * float4(resolution, resolution);
}

float generatedText(float2 pixel, float2 anchor, float scalePx, uint labelId) {
    float coverage = 0.0;
    [loop] for (int index = 0; index < uiLabelLength(labelId); ++index) {
        float2 at = anchor + float2(index * SUI3_ADVANCE * scalePx, 0.0);
        coverage = max(coverage, sui3Glyph(pixel, at, scalePx, uiLabelCode(labelId, index)));
    }
    return coverage;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 resolution = float2(width, height);
    float2 pixel = float2(tid.xy) + 0.5;
    Sui3Theme theme = sui3Theme(float3(0.82, 0.82, 0.82));
    float3 color = theme.field;

    float margin = max(18.0, min(resolution.x, resolution.y) * 0.04);
    float4 frame = float4(margin, margin, resolution.x - margin, resolution.y - margin);
    color += theme.rule * sui3Frame(pixel, frame);
    color += theme.ink * generatedText(
        pixel,
        float2(frame.x + 18.0, frame.y + 18.0),
        1.0,
        UI_LABEL_TITLE
    );

    float4 rail = uiPixels(UI_RECT_AMOUNT, resolution);
    color += sui3Rail(pixel, rail, amount, theme);
    color += theme.dim * generatedText(
        pixel,
        float2(rail.x, rail.y - 20.0),
        1.0,
        UI_LABEL_CONTROL_AMOUNT
    );

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
