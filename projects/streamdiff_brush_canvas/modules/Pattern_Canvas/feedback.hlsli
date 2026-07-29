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
// Zoom Speed keeps its historical kick multiplier, so existing looks are
// unchanged. Kick Zoom adds a rate that exists ONLY while the envelope is open,
// which is what lets Zoom Speed sit at 0 - perfectly still between beats - and
// still punch on the kick. Multiplying could never do that: anything times zero
// is zero, so at Zoom Speed 0 the kick had nothing to scale.
//
// At kick_zoom = 0 this reduces to exp2(zoom * 2 * dt * control_gain * kick),
// which is byte-for-byte the previous expression.
float pcZoomFactor(float kickAmount, float kick, float dt)
{
    float master = max(control_gain, 0.0);
    float zoomRate = zoom * master * kick + kick_zoom * kickAmount * master;
    return exp2((zoomRate * 2.0) * dt);
}

#endif
