struct SequencerData {
    float env1; float gate1; float trig1; float env2;
    float gate2; float trig2; float env3; float gate3;
    float trig3; float env4; float gate4; float trig4;
    float clockPhase; float stepIndex; float pad1; float pad2;
};

RWStructuredBuffer<SequencerData> OutputBuffer : register(u0);

float bitOn(int pattern, int index) {
    return ((pattern >> index) & 1) != 0 ? 1.0 : 0.0;
}

float envelope(float age, float held, float lev) {
    if (age < 0.0 || age > held + release) return 0.0;
    if (age < attack) return lev * saturate(age / attack);
    if (age < attack + decay) return lerp(lev, lev * sustain, saturate((age - attack) / decay));
    if (age < held) return lev * sustain;
    return lev * sustain * (1.0 - saturate((age - held) / release));
}

float laneEnvelope(int pattern, float level, float phase, int step, float stepTime, out float gate, out float trig) {
    int current = step & 7;
    int previous = (step + 7) & 7;
    float onNow = bitOn(pattern, current);
    float onPrev = bitOn(pattern, previous);
    float age = phase * stepTime;
    float held = gate_length * stepTime;
    float env = 0.0;
    if (onNow > 0.5) env = envelope(age, held, level);
    else if (onPrev > 0.5) env = envelope(age + stepTime, held, level);
    gate = (onNow > 0.5 && age < held) ? 1.0 : 0.0;
    trig = (onNow > 0.5) ? exp(-age * 180.0) : 0.0;
    return env;
}

float beatMultiplier(int index) {
    if (index <= 0) return 1.0;
    if (index == 1) return 2.0;
    if (index == 2) return 4.0;
    return 8.0;
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    float stepRate = max(0.001, tempo / 60.0 * beatMultiplier((int)steps_per_beat));
    float stepTime = 1.0 / stepRate;
    float clock = _Time * stepRate;
    int rawStep = (int)floor(clock);
    float swungClock = clock + (((rawStep & 1) != 0) ? swing * 0.5 : 0.0);
    int step = (int)floor(swungClock);
    float phase = frac(swungClock);

    SequencerData d;
    d.env1 = laneEnvelope(pattern_1, level_1, phase, step, stepTime, d.gate1, d.trig1);
    d.env2 = laneEnvelope(pattern_2, level_2, phase, step, stepTime, d.gate2, d.trig2);
    d.env3 = laneEnvelope(pattern_3, level_3, phase, step, stepTime, d.gate3, d.trig3);
    d.env4 = laneEnvelope(pattern_4, level_4, phase, step, stepTime, d.gate4, d.trig4);
    d.clockPhase = phase;
    d.stepIndex = (float)(step & 7) / 8.0;
    d.pad1 = 0.0; d.pad2 = 0.0;
    OutputBuffer[0] = d;
}
