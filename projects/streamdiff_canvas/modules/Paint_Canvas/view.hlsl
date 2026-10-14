// Paint_Canvas / view - the canvas itself, per pixel, on the instrument ground: the painted image
// (the clean pass - the module's real Canvas output, shown unaltered: it is data, not chrome)
// fitted under the toolbar and panned / zoomed by paint_state, and the brush footprint at the
// pointer as an inverting ring, so it reads over any paint; and, when the canvas leaves a margin,
// the module's Depth and Mask outputs as thumbnails beside it. Type and chrome - toolbar, CLEAR,
// readouts, the frames and the keycap footer - are recorded by layout.hlsl and drawn over this by
// ui.hlsl.
#include "../_shared/ui/il_core.hlsli"
#include "paint_view.hlsli"

StructuredBuffer<float4> PaintState : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;
    float2 res = float2(width, height);
    float2 px = float2(id.xy) + 0.5;
    float4 view = PaintState[19];
    float2 canvasUv = pcPxToCanvas(px, res, view.xy, view.z);

    float3 color = IL_FIELD;
    bool inside = all(canvasUv >= 0.0) && all(canvasUv <= 1.0) && id.y >= (uint)PC_TOOLBAR_PX;
    if (inside) color = _Tex0.SampleLevel(LinearSampler, canvasUv, 0).rgb;

    if (inside) {
        float2 pointerCanvas = pcPxToCanvas(_ViewportPointerPosition * res, res, view.xy, view.z);
        float2 d = (canvasUv - pointerCanvas) * float2(0.8, 1.0);
        // Match the inverse texture transform used by poster_update.hlsl.
        float a = radians(-rotation);
        d = mul(float2x2(cos(a), -sin(a), sin(a), cos(a)), d);
        d.x /= max(brush_aspect, 0.05);
        float effectiveBrushSize = PaintState[0].y;
        float ring = abs(length(d) - effectiveBrushSize * 0.5);
        float pixelCanvas = 1.0 / max(PC_CANVAS_PIXELS.y * pcFitScale(res) * view.z, 1.0);
        float cursor = smoothstep(pixelCanvas * 2.2, pixelCanvas * 0.55, ring);
        color = lerp(color, 1.0 - color, cursor * 0.88);
    }

    // secondary previews of real images: through ptInset, so a white mask cannot outrank the readouts
    float4 depthR, maskR;
    if (pcThumbs(res, view.xy, view.z, depthR, maskR))
    {
        if (ilIn(px, depthR)) color = ptInset(_Tex2.SampleLevel(LinearSampler, (px - depthR.xy) / (depthR.zw - depthR.xy), 0).rgb);
        if (ilIn(px, maskR)) color = ptInset(_Tex3.SampleLevel(LinearSampler, (px - maskR.xy) / (maskR.zw - maskR.xy), 0).rgb);
    }
    OutputUAV[id.xy] = float4(saturate(color), 1.0);
}
