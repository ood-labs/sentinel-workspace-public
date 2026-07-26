// AUTOPSIA — the operator's stylus.
//
// Single-threaded reduction of the real viewport event stream into a persistent
// stimulus bank. This is the node that closes the perceptual loop: what the
// operator deposits here deforms the specimen, which changes what the Features
// node finds, which changes the instrument's hypothesis about the specimen.
//
// Slot [16] carries control state (radius, mode, next index) and is deliberately
// left flags=0 so downstream consumers skip it as an inactive record.
#include "types.hlsli"

RWStructuredBuffer<StimulusRecord> Stim : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    StimulusRecord ctrl = Stim[CTRL_SLOT];

    if ((ctrl.flags & CTRL_INIT) == 0u || isnan(ctrl.radius)) {
        [loop] for (uint c = 0u; c < STIM_SLOTS; ++c) Stim[c] = emptyStimulus();
        ctrl = emptyStimulus();
        ctrl.radius = 0.085;
        ctrl.mode = 0.0;
        ctrl.id = 0u;
        ctrl.flags = CTRL_INIT;
    }

    // wheel resizes the deposit radius (frame-summed notches)
    ctrl.radius = clamp(ctrl.radius * (1.0 + _ViewportWheelDelta * 0.10), 0.015, 0.34);

    float dt = min(_DeltaTime, 0.05);

    // ---- age and fade the existing bank ------------------------------------
    [loop] for (uint a = 0u; a < STIM_SLOTS; ++a) {
        StimulusRecord s = Stim[a];
        if (!stimActive(s)) continue;
        s.age += dt;
        if (hold_stimuli < 0.5) {
            s.strength -= dt / max(stim_life, 0.05);
            if (s.strength <= 0.0) { s.flags = 0u; s.strength = 0.0; }
        }
        Stim[a] = s;
    }

    // ---- consume the real event stream -------------------------------------
    bool clearAll = false;
    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];

        // keys: X clears the bank, M toggles deposit mode
        if (e.type == 4u && e.phase == 1u && e.code == 24u) clearAll = true;
        if (e.type == 4u && e.phase == 1u && e.code == 13u) ctrl.mode = 1.0 - ctrl.mode;

        bool leftPress  = (e.type == 2u && e.phase == 1u && e.code == 0u);
        bool rightPress = (e.type == 2u && e.phase == 1u && e.code == 1u);
        bool click      = (e.type == 5u && e.code == 1u);
        bool drag       = (e.type == 5u && e.code == 3u && e.phase != 8u);

        if (!(leftPress || rightPress || click || drag)) continue;

        uint slot = ctrl.id % STIM_SLOTS;
        StimulusRecord n = emptyStimulus();
        n.position = saturate(e.position);
        float2 d = e.delta;
        n.direction = (length(d) > 1e-5) ? normalize(d) : float2(0.0, 1.0);
        n.radius = ctrl.radius * (drag ? 0.72 : 1.0);
        n.strength = drag ? 0.62 : 1.0;
        n.age = 0.0;
        // right button always deposits an incision regardless of the held mode
        n.mode = rightPress ? 1.0 : ctrl.mode;
        n.id = ctrl.id;
        n.flags = STIM_ACTIVE;
        Stim[slot] = n;
        ctrl.id = ctrl.id + 1u;
    }

    if (clearAll) {
        [loop] for (uint k = 0u; k < STIM_SLOTS; ++k) Stim[k] = emptyStimulus();
    }

    // ---- probe: a non-pointer stimulus source -------------------------------
    // Slot 15 is reserved for an automatable deposit driven by parameters
    // rather than the mouse, so the specimen can be deformed from expressions,
    // OSC, or the performance deck — and so the stimulus->specimen contract can
    // be exercised without a hand on the pointer.
    if (probe_enable > 0.5) {
        StimulusRecord pr = emptyStimulus();
        pr.position = saturate(float2(probe_x, probe_y));
        pr.direction = float2(cos(probe_angle), sin(probe_angle));
        pr.radius = max(probe_radius, 0.008);
        pr.strength = saturate(probe_strength);
        pr.age = Stim[STIM_SLOTS - 1u].age + dt;
        pr.mode = (probe_mode > 0.5) ? 1.0 : 0.0;
        pr.id = 999999u;
        pr.flags = STIM_ACTIVE;
        Stim[STIM_SLOTS - 1u] = pr;
    }

    if (ctrl.id > 1000000u) ctrl.id = 0u;
    Stim[CTRL_SLOT] = ctrl;
}
