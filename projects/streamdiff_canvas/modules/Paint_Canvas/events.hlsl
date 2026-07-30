// Structured state records:
//  0 = generation, effective brush size, last parameter size, init marker
//  1 = last painted canvas x/y, last angle, drag active
//  2..17 = stamp canvas x/y, angle, generation
// 18 = clear flag, previous clear button, queue count, middle-gesture suppression
// 19 = view pan x/y (canvas UV), zoom, middle-button state
RWStructuredBuffer<float4> OutputBuffer : register(u0);

static const float2 PC_CANVAS_PIXELS = float2(1080.0, 1350.0);
static const float PC_TOOLBAR_PX = 32.0;

float4 pcClearRect()
{
    float2 safeResolution = max(_Resolution.xy, float2(1.0, 1.0));
    return float4((safeResolution.x - 68.0) / safeResolution.x, 5.0 / safeResolution.y,
                  (safeResolution.x - 8.0) / safeResolution.x, 27.0 / safeResolution.y);
}

float pcFitScale()
{
    float availableHeight = max(_Resolution.y - PC_TOOLBAR_PX, 1.0);
    return max(min(_Resolution.x / PC_CANVAS_PIXELS.x, availableHeight / PC_CANVAS_PIXELS.y), 0.0001);
}

float2 pcScreenToCanvas(float2 screenUv, float2 viewPan, float viewZoom)
{
    float availableHeight = max(_Resolution.y - PC_TOOLBAR_PX, 1.0);
    float2 centerPx = float2(_Resolution.x * 0.5, PC_TOOLBAR_PX + availableHeight * 0.5);
    float2 screenPx = screenUv * _Resolution.xy;
    return (screenPx - centerPx) / (PC_CANVAS_PIXELS * pcFitScale() * max(viewZoom, 0.01)) + 0.5 + viewPan;
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float4 ctrl = OutputBuffer[0];
    float4 dragState = OutputBuffer[1];
    float4 meta = OutputBuffer[18];
    float4 view = OutputBuffer[19];
    if (ctrl.a < 0.5) {
        ctrl = float4(0.0, brush_size, brush_size, 1.0);
        dragState = float4(0.5, 0.5, rotation, 0.0);
        meta = 0.0;
        view = float4(0.0, 0.0, 1.0, 0.0);
    }
    if (abs(brush_size - ctrl.z) > 0.00001) {
        ctrl.y = brush_size;
        ctrl.z = brush_size;
    }

    float4 queue[16];
    uint queued = 0u;
    float clearValue = clear_canvas != 0 ? 1.0 : 0.0;
    bool clearNow = abs(clearValue - meta.y) > 0.5;
    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 4u && e.phase == 1u && e.code == 24u) clearNow = true; // X
        if ((e.flags & VIEWPORT_EVENT_FLAG_HOST_CONSUMED) != 0u) continue;

        if (e.type == 4u && e.phase == 1u) {
            if (e.code == 6u) view = float4(0.0, 0.0, 1.0, view.w); // F = fit
        }
        float4 clearRect = pcClearRect();
        if (e.type == 2u && e.code == 0u && e.phase == 1u &&
            all(e.position >= clearRect.xy) && all(e.position <= clearRect.zw)) {
            clearNow = true;
        }
        if (e.type == 2u && e.code == 0u && e.phase == 1u) {
            // A new left-button action also recovers from any interrupted pan capture.
            meta.w = 0.0;
        }
        if (e.type == 2u && e.code == 2u) {
            if (e.phase == 1u) {
                view.w = 1.0;
                meta.w = 1.0;
                dragState.w = 0.0;
            }
            if (e.phase == 3u || e.phase == 8u) view.w = 0.0;
        }
        if (e.type == 1u && view.w > 0.5) {
            float2 deltaCanvas = e.delta * _Resolution.xy / (PC_CANVAS_PIXELS * pcFitScale() * max(view.z, 0.01));
            view.xy -= deltaCanvas;
        }
        if (e.type == 3u && e.position.y * _Resolution.y >= PC_TOOLBAR_PX) {
            float notches = abs(e.value) > 0.001 ? e.value : e.delta.y;
            if ((e.modifiers & VIEWPORT_MODIFIER_ALT) != 0u) {
                ctrl.y = clamp(ctrl.y * pow(1.12, notches), 0.025, 0.50);
            } else {
                float2 anchorBefore = pcScreenToCanvas(e.position, view.xy, view.z);
                view.z = clamp(view.z * pow(1.12, notches), 0.35, 12.0);
                float2 baseAfter = pcScreenToCanvas(e.position, 0.0, view.z);
                view.xy = anchorBefore - baseAfter;
            }
        }

        // Gesture events do not carry their originating pointer button in ABI v1.
        // Latch middle-button ownership from the raw pointer event and discard its
        // resulting click/drag gesture so panning can never enqueue paint stamps.
        if (e.type == 5u && meta.w > 0.5) {
            if (e.phase == 7u || e.phase == 8u) meta.w = 0.0;
            continue;
        }

        bool click = (e.type == 5u && e.code == 1u);
        bool drag = (e.type == 5u && e.code == 3u);
        float2 canvasPos = pcScreenToCanvas(e.position, view.xy, view.z);
        bool onCanvas = e.position.y * _Resolution.y >= PC_TOOLBAR_PX && all(canvasPos >= 0.0) && all(canvasPos <= 1.0);
        if (click && onCanvas && queued < 16u) queue[queued++] = float4(canvasPos, rotation, 0.0);
        if (drag && onCanvas) {
            if (e.phase == 5u) {
                dragState = float4(canvasPos, rotation, 1.0);
                if (queued < 16u) queue[queued++] = float4(canvasPos, rotation, 0.0);
            } else if (e.phase == 6u || e.phase == 7u) {
                float2 delta = canvasPos - dragState.xy;
                float dist = length(delta * float2(0.8, 1.0));
                float stepSize = max(ctrl.y * max(spacing, 0.05), 0.003);
                uint steps = (uint)clamp(ceil(dist / stepSize), 1.0, 16.0);
                float tangent = degrees(atan2(delta.y, delta.x));
                float stampAngle = (align_to_stroke != 0) ? tangent : rotation;
                [loop] for (uint s = 1u; s <= steps && queued < 16u; ++s) {
                    float t = (float)s / (float)steps;
                    queue[queued++] = float4(lerp(dragState.xy, canvasPos, t), stampAngle, 0.0);
                }
                dragState = float4(canvasPos, stampAngle, e.phase == 7u ? 0.0 : 1.0);
            } else if (e.phase == 8u) dragState.w = 0.0;
        }
    }

    if (clearNow || queued > 0u) ctrl.x += 1.0;
    if (ctrl.x > 1000.0) ctrl.x = 1.0;
    OutputBuffer[0] = ctrl;
    OutputBuffer[1] = dragState;
    [unroll] for (uint q = 0u; q < 16u; ++q) {
        float4 entry = float4(0.0, 0.0, rotation, ctrl.x);
        if (q < queued) entry = float4(queue[q].xyz, ctrl.x);
        OutputBuffer[2u + q] = entry;
    }
    OutputBuffer[18] = float4(clearNow ? 1.0 : 0.0, clearValue, (float)queued, meta.w);
    OutputBuffer[19] = view;
}
