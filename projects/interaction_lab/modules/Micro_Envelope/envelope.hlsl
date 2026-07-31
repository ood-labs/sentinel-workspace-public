RWStructuredBuffer<float4> EnvelopeState : register(u0);

static const float MAGIC = 39241.0;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 state = EnvelopeState[0];
    float4 meta = EnvelopeState[1];
    if (meta.w != MAGIC || isnan(state.x)) {
        state = float4(gate ? 1.0 : 0.0, gate ? 1.0 : 0.0, 0.0, 0.0);
        meta = float4(gate ? 1.0 : 0.0, 0.0, 0.0, MAGIC);
    }

    float target = gate ? 1.0 : 0.0;
    float dt = min(max(_DeltaTime, 0.0), 0.05);
    float seconds = target > state.x ? max(attack, 0.001) : max(release, 0.001);
    float alpha = 1.0 - exp(-dt / seconds);
    float valueNow = lerp(state.x, target, alpha);

    bool rose = target > 0.5 && meta.x <= 0.5;
    bool fell = target <= 0.5 && meta.x > 0.5;
    state = float4(valueNow, target,
                   state.z + (rose ? 1.0 : 0.0),
                   state.w + (fell ? 1.0 : 0.0));
    meta.x = target;
    EnvelopeState[0] = state;
    EnvelopeState[1] = meta;
}
