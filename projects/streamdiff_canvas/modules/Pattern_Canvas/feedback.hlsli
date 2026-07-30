#ifndef PATTERN_CANVAS_FEEDBACK_HLSLI
#define PATTERN_CANVAS_FEEDBACK_HLSLI

// The feedback zoom rate, shared by every pass that moves the canvas: the colour
// feedback (accumulate), the depth feedback (accumulate_depth), the live stamp
// pose (stamp_pose) and the Spawn Point records (spawn_points).
//
// These four MUST agree exactly. The point records describe where the pixels
// went, so any divergence walks the tracer off the imagery within a few frames.
// The expression used to be copy-pasted into all four; it lives here now so a
// change cannot land in three of them.
//
float pcZoomFactor(float dt)
{
    float master = max(control_gain, 0.0);
    float zoomRate = zoom * master;
    return exp2((zoomRate * 2.0) * dt);
}

#endif
