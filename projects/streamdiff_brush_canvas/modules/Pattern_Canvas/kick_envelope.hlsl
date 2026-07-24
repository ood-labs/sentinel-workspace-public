// Held-D ADSR envelope shared by both the feedback texture transform and the
// Spawn Points transform. x=level, y=stage, z=release start, w=initialized.
RWStructuredBuffer<float4> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    if (state.w < 0.5)
        state = float4(0.0, 0.0, 0.0, 1.0);

    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float level = saturate(state.x);
    int stage = (int)round(state.y); // 0 idle, 1 attack, 2 decay, 3 sustain, 4 release
    bool held = ViewportKeyDown(3u); // C

    if (held) {
        if (stage == 0 || stage == 4)
            stage = 1;

        if (stage == 1) {
            level += dt / max(kick_attack, 0.001);
            if (level >= 1.0) {
                level = 1.0;
                stage = 2;
            }
        }
        else if (stage == 2) {
            float sustain = saturate(kick_sustain);
            level -= (1.0 - sustain) * dt / max(kick_decay, 0.001);
            if (level <= sustain) {
                level = sustain;
                stage = 3;
            }
        }
        else if (stage == 3) {
            level = saturate(kick_sustain);
        }
    }
    else {
        if (stage != 0 && stage != 4) {
            stage = 4;
            state.z = level;
        }

        if (stage == 4) {
            level -= max(state.z, 0.0) * dt / max(kick_release, 0.001);
            if (level <= 0.0) {
                level = 0.0;
                stage = 0;
                state.z = 0.0;
            }
        }
    }

    state.x = saturate(level);
    state.y = (float)stage;
    state.w = 1.0;
    OutputBuffer[0] = state;
}
