// LaserViz shared show lifecycle timeline.
//
// One master phase scrubs the whole look:
//   0 -> IN -> BODY/loops -> OUT -> 1
//
// `animation_speed` can auto-advance phase. `time_mode` controls whether
// secondary animation clocks keep breathing in real time or derive from phase
// for deterministic captures and cue scrubs.

#ifndef LASERVIZ_SHOW_TIMELINE_HLSLI
#define LASERVIZ_SHOW_TIMELINE_HLSLI

float stMasterPhase(float phase, float animation_speed, float t) {
    return (animation_speed > 0.0) ? frac(saturate(phase) + t * animation_speed)
                                   : saturate(phase);
}

float stStage(float p, float start, float end) {
    return saturate((p - start) / max(end - start, 1e-4));
}

float stStageSmooth(float p, float start, float end) {
    return smoothstep(0.0, 1.0, stStage(p, start, end));
}

float stPulse(float p, float start, float peak, float release, float end) {
    return saturate(min(stStage(p, start, peak), 1.0 - stStage(p, release, end)));
}

float stLifeIn(float p, float in_end) {
    return stStageSmooth(p, 0.0, max(in_end, 1e-3));
}

float stLifeOut(float p, float out_start) {
    return 1.0 - stStageSmooth(p, min(out_start, 0.999), 1.0);
}

float stLife(float p, float in_end, float out_start) {
    return min(stLifeIn(p, in_end), stLifeOut(p, out_start));
}

float stBody(float p, float in_end, float out_start) {
    return stStage(p, in_end, out_start);
}

float stEvent(float b, float pos, float width) {
    float w = max(width, 1e-3);
    return saturate(1.0 - abs(b - pos) / w);
}

float stEventSmooth(float b, float pos, float width) {
    float e = stEvent(b, pos, width);
    return e * e * (3.0 - 2.0 * e);
}

float stLoopGate(float b, float pos, float half_width, float blend) {
    float lo = pos - half_width;
    float hi = pos + half_width;
    float bl = max(blend, 1e-3);
    return saturate(min(stStage(b, lo, lo + bl), 1.0 - stStage(b, hi - bl, hi)));
}

float stLoopClock(float time_mode, float t, float loop_speed,
                  float b, float pos, float half_width, float det_cycles) {
    if (time_mode >= 0.5) {
        float lp = stStage(b, pos - half_width, pos + half_width);
        return lp * max(det_cycles, 0.0);
    }
    return t * loop_speed;
}

float stClock(float time_mode, float t, float motion_speed, float p, float det_scale) {
    return (time_mode >= 0.5) ? p * det_scale : t * motion_speed;
}

float stCycleClock(float loop_phase, float loop_speed, float t) {
    return saturate(loop_phase) + t * loop_speed;
}

float2 stDualClock(float t, float v_a, float v_b) {
    return float2(t * v_a, t * v_b);
}

#endif
