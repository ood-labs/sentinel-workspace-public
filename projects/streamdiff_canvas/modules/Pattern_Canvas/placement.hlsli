#ifndef PATTERN_CANVAS_PLACEMENT_HLSLI
#define PATTERN_CANVAS_PLACEMENT_HLSLI

// stamp_pose and spawn_points reach the shared feedback zoom rate through here.
#include "feedback.hlsli"

static const float PI = 3.14159265359;
static const float TAU = 6.28318530718;

uint pcHash(uint value)
{
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

float pcRandom(uint hit, uint salt)
{
    uint value = hit ^ salt ^ asuint(seed + 0.12345);
    return (pcHash(value) & 0x00ffffffu) / 16777216.0;
}

float2 pcBorderPoint(float t, out float tangent)
{
    float edge = frac(t) * 4.0;
    if (edge < 1.0) {
        tangent = 0.0;
        return float2(lerp(0.10, 0.90, edge), 0.10);
    }
    if (edge < 2.0) {
        tangent = PI * 0.5;
        return float2(0.90, lerp(0.10, 0.90, edge - 1.0));
    }
    if (edge < 3.0) {
        tangent = PI;
        return float2(lerp(0.90, 0.10, edge - 2.0), 0.90);
    }
    tangent = -PI * 0.5;
    return float2(0.10, lerp(0.90, 0.10, edge - 3.0));
}

void pcPlacement(uint cycle, out float2 center, out float stampSize, out float angle)
{
    uint count = (uint)clamp(pattern_count, 4, 36);
    uint index = cycle % count;
    float i = (float)index;
    float n = max((float)count, 1.0);
    float pathAngle = 0.0;
    int mode = clamp(pattern_mode, 0, 4);

    if (mode == 0) {
        center = float2(lerp(0.09, 0.91, pcRandom(cycle, 11u)),
                        lerp(0.09, 0.91, pcRandom(cycle, 17u)));
    }
    else if (mode == 1) {
        uint columns = (uint)ceil(sqrt((float)count * 0.82));
        uint rows = (count + columns - 1u) / columns;
        uint shifted = (index + (uint)floor(pattern_phase * n)) % count;
        uint column = shifted % columns;
        uint row = shifted / columns;
        center = float2(((float)column + 0.5) / (float)columns,
                        ((float)row + 0.5) / (float)rows);
        center = lerp(0.10.xx, 0.90.xx, center);
    }
    else if (mode == 2) {
        float t = count > 1u ? i / (n - 1.0) : 0.0;
        float spiralAngle = i * 2.39996323 + pattern_phase * TAU;
        float radius = lerp(0.04, 0.38, sqrt(t));
        center = 0.5.xx + float2(cos(spiralAngle) * radius,
                                 sin(spiralAngle) * radius * 0.82);
        pathAngle = spiralAngle + PI * 0.5;
    }
    else if (mode == 3) {
        float t = (i + 0.5) / n;
        float wavePhase = t * TAU * 1.5 + pattern_phase * TAU;
        center = float2(lerp(0.08, 0.92, t), 0.5 + sin(wavePhase) * 0.30);
        float dx = 0.84;
        float dy = cos(wavePhase) * 0.30 * TAU * 1.5;
        pathAngle = atan2(dy, dx);
    }
    else {
        center = pcBorderPoint(i / n + pattern_phase, pathAngle);
    }

    float2 randomOffset = float2(pcRandom(cycle, 31u), pcRandom(cycle, 37u)) - 0.5;
    center = clamp(center + randomOffset * position_jitter, 0.04.xx, 0.96.xx);
    // Contract the finished placement toward the canvas centre. Applied last, on
    // purpose: every mode carries its own hardcoded inset (Grid 0.10-0.90, Border
    // 0.10-0.90, Spiral a 0.38 radius), and scaling here shrinks all of them by
    // the same factor instead of needing a margin term threaded through each one.
    center = 0.5.xx + (center - 0.5.xx) * clamp(spawn_area, 0.05, 1.0);
    stampSize = cutout_scale * lerp(1.0 - scale_variation,
                                    1.0 + scale_variation,
                                    pcRandom(cycle, 43u));
    angle = radians(rotation + (pcRandom(cycle, 47u) - 0.5) * rotation_jitter);
    if (follow_pattern != 0 && mode >= 2) angle += pathAngle;
}

#endif
