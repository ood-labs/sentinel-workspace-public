#include "placement.hlsli"

struct SpawnPoint
{
    float x;
    float y;
    uint sequence;
    uint active;
};

RWStructuredBuffer<SpawnPoint> OutputBuffer : register(u0);
StructuredBuffer<float4> CanvasState : register(t0);

float2 pcForwardFeedback(float2 uv, out bool visible)
{
    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 pivot = feedback_pivot;
    float gain = max(control_gain, 0.0);
    float2 drift = float2(pan.x * aspect, pan.y) * (dt * gain);
    float zoomFactor = pcZoomFactor(dt);
    float angle = radians(feedback_rotation_speed) * dt;
    float cs = cos(angle);
    float sn = sin(angle);

    float2 p = float2((uv.x - pivot.x) * aspect, uv.y - pivot.y);
    p = float2(cs * p.x - sn * p.y,
               sn * p.x + cs * p.y) * zoomFactor + drift;
    float2 transformed = pivot + float2(p.x / aspect, p.y);

    // feedback_edge_mode is an IMAGE sampling rule and must not be applied to
    // markers. Clamp's saturate() pinned every escaped point onto the border and
    // left it active forever, so the corners silted up with dead markers; Wrap's
    // frac() and Mirror teleported points to the far side of the canvas, and the
    // tracer - which threads a spline through spawn history in chronological
    // order - whipped a full-width segment across the frame on every wrap. Both
    // read as the trace flipping out for no reason, and neither marker describes
    // a stamp the viewer can actually see at that coordinate.
    //
    // A spawn point is a discrete record of where one stamp was placed. Once the
    // feedback transform carries it off the canvas it no longer marks anything,
    // in any edge mode, so it dies here regardless of how the texture is tiled.
    visible = transformed.x >= 0.0 && transformed.x <= 1.0 &&
              transformed.y >= 0.0 && transformed.y <= 1.0;
    return transformed;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 state = CanvasState[0];
    float action = state.y;

    if (action < -0.5) {
        [unroll] for (uint i = 0u; i < 64u; ++i) {
            SpawnPoint emptyPoint = OutputBuffer[i];
            emptyPoint.active = 0u;
            OutputBuffer[i] = emptyPoint;
        }
        return;
    }

    // Compact surviving history in chronological order while applying the
    // exact forward transform corresponding to the canvas's inverse sampling.
    uint writeIndex = 0u;
    [loop] for (uint readIndex = 0u; readIndex < 64u; ++readIndex) {
        SpawnPoint record = OutputBuffer[readIndex];
        if (record.active == 0u) continue;

        bool visible = true;
        float2 position = float2(record.x, record.y);
        if (feedback_enabled != 0) position = pcForwardFeedback(position, visible);
        if (!visible) continue;

        record.x = position.x;
        record.y = position.y;
        OutputBuffer[writeIndex] = record;
        ++writeIndex;
    }

    [loop] for (uint clearIndex = writeIndex; clearIndex < 64u; ++clearIndex) {
        SpawnPoint emptyPoint = OutputBuffer[clearIndex];
        emptyPoint.active = 0u;
        OutputBuffer[clearIndex] = emptyPoint;
    }

    // Stage 1 creates the point once; white/color reveal stages reuse it.
    if (action > 0.5 && action < 1.5) {
        if (writeIndex >= 64u) {
            [unroll] for (uint shiftIndex = 0u; shiftIndex < 63u; ++shiftIndex)
                OutputBuffer[shiftIndex] = OutputBuffer[shiftIndex + 1u];
            writeIndex = 63u;
        }

        uint cycle = (uint)max(state.x, 0.0);
        float2 center;
        float stampSize;
        float angle;
        pcPlacement(cycle, center, stampSize, angle);

        SpawnPoint spawned;
        spawned.x = center.x;
        spawned.y = center.y;
        spawned.sequence = cycle;
        spawned.active = 1u;
        OutputBuffer[writeIndex] = spawned;
    }
}
