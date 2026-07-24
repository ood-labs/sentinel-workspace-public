RWTexture2D<float4> OutputUAV : register(u0);

struct SequencerData {
    float env1; float gate1; float trig1; float env2;
    float gate2; float trig2; float env3; float gate3;
    float trig3; float env4; float gate4; float trig4;
    float clockPhase; float stepIndex; float pad1; float pad2;
};
StructuredBuffer<SequencerData> Values : register(t0);

float laneValue(SequencerData d, int i) {
    if (i == 0) return d.env1; if (i == 1) return d.env2;
    if (i == 2) return d.env3; return d.env4;
}
float lanePattern(int i) {
    if (i == 0) return pattern_1; if (i == 1) return pattern_2;
    if (i == 2) return pattern_3; return pattern_4;
}
float laneLevel(int i) {
    if (i == 0) return level_1; if (i == 1) return level_2;
    if (i == 2) return level_3; return level_4;
}
float3 laneColor(int i) {
    if (i == 0) return float3(1.0, 0.72, 0.20);
    if (i == 1) return float3(0.92, 0.92, 0.92);
    if (i == 2) return float3(0.68, 0.82, 0.74);
    return float3(0.78, 0.62, 0.42);
}
float beatMultiplier(int index) {
    if (index <= 0) return 1.0;
    if (index == 1) return 2.0;
    if (index == 2) return 4.0;
    return 8.0;
}
float envelopeAt(float age, float stepTime, float lev) {
    float held = gate_length * stepTime;
    if (age < 0.0 || age > held + release) return 0.0;
    if (age < attack) return lev * saturate(age / attack);
    if (age < attack + decay) return lerp(lev, lev * sustain, saturate((age - attack) / decay));
    if (age < held) return lev * sustain;
    return lev * sustain * (1.0 - saturate((age - held) / release));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float3 col = float3(0.015, 0.016, 0.019);
    SequencerData d = Values[0];

    float stepRate = max(0.001, tempo / 60.0 * beatMultiplier((int)steps_per_beat));
    float stepTime = 1.0 / stepRate;
    float rawClock = _Time * stepRate;
    int rawStep = (int)floor(rawClock);
    float swungClock = rawClock + (((rawStep & 1) != 0) ? swing * 0.5 : 0.0);
    int currentStep = ((int)floor(swungClock)) & 7;
    float currentPhase = frac(swungClock);

    // A quiet top rail makes the 8-step reading order explicit.
    float railX0 = 0.13;
    float railX1 = 0.96;
    float railY = 0.075;
    float rail = smoothstep(0.004, 0.001, abs(uv.y - railY));
    col += float3(0.20, 0.19, 0.17) * rail * step(railX0, uv.x) * step(uv.x, railX1);
    float railPlayhead = railX0 + (currentStep + currentPhase) / 8.0 * (railX1 - railX0);
    col += float3(1.0, 0.72, 0.20) * smoothstep(0.006, 0.001, abs(uv.x - railPlayhead)) * step(0.03, uv.y) * step(uv.y, 0.105);

    float laneTop = 0.13;
    float laneH = 0.18;
    float laneGap = 0.205;
    float gridX0 = 0.13;
    float gridX1 = 0.96;
    float meterX0 = 0.045;
    float meterX1 = 0.095;

    for (int lane = 0; lane < 4; ++lane) {
        float y0 = laneTop + lane * laneGap;
        float y1 = y0 + laneH;
        float3 c = laneColor(lane);
        float v = laneValue(d, lane);
        float inLane = step(y0, uv.y) * step(uv.y, y1);

        // Live envelope meter, separated from the step pattern.
        float meterFill = step(y0 + laneH * (1.0 - saturate(v)), uv.y) * step(uv.y, y1);
        float meterBox = step(meterX0, uv.x) * step(uv.x, meterX1) * inLane;
        col += float3(0.055, 0.060, 0.065) * meterBox;
        col += c * meterFill * meterBox * 0.9;

        for (int s = 0; s < 8; ++s) {
            float sx0 = lerp(gridX0, gridX1, (float)s / 8.0) + 0.004;
            float sx1 = lerp(gridX0, gridX1, (float)(s + 1) / 8.0) - 0.004;
            float cellIn = step(sx0, uv.x) * step(uv.x, sx1) * inLane;
            float on = ((int)lanePattern(lane) >> s) & 1;
            float isCurrent = (s == currentStep) ? 1.0 : 0.0;

            // Each cell is a tiny ADSR plot: attack rises, decay falls,
            // sustain holds, and release returns to the baseline.
            float local = saturate((uv.x - sx0) / max(0.001, sx1 - sx0));
            float age = local * stepTime;
            float curve = envelopeAt(age, stepTime, laneLevel(lane));
            float curveY = y1 - 0.025 - curve * (laneH - 0.045);
            float curveLine = smoothstep(0.012, 0.002, abs(uv.y - curveY));
            float baseline = smoothstep(0.006, 0.001, abs(uv.y - (y1 - 0.022)));

            float3 cellBg = isCurrent > 0.5 ? float3(0.075, 0.070, 0.058) : float3(0.030, 0.033, 0.038);
            col = lerp(col, cellBg, cellIn);
            col += float3(0.10, 0.105, 0.11) * baseline * cellIn * (1.0 - on);
            col += c * curveLine * cellIn * on;
            col += c * smoothstep(0.010, 0.001, abs(uv.x - sx0)) * inLane * 0.22;
            col += float3(1.0, 0.82, 0.42) * cellIn * smoothstep(0.008, 0.001, abs(uv.x - (sx0 + local * (sx1-sx0)))) * isCurrent * 0.35;
        }

        // Current-step playhead crosses the active cell, not the whole lane.
        float playX = lerp(gridX0, gridX1, (currentStep + currentPhase) / 8.0);
        col += float3(1.0, 0.72, 0.20) * smoothstep(0.005, 0.001, abs(uv.x - playX)) * inLane;
    }

    OutputUAV[px] = float4(saturate(col), 1.0);
}
