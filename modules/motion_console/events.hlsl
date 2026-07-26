// Motion Console - burst trigger and envelope.
//
// This pass exists for exactly one control. Every other control on the desk is
// a host-owned `viewport.controls` entry, because that gets undo, presets, OSC
// and project save for free. Burst cannot use that path: the `button` kind is
// backed by `type: button`, which 3C measured as a one-way latch in the shader
// -- it fires and never releases, and survives force_reload.
//
// So burst is a raw hit-tested click producing a REAL ENVELOPE, which is what
// the v1 desk should have had anyway. `if (burst) lfo4 = 1.0` was not a burst;
// it was a clamp. A burst has an attack and a decay and then it is over, and
// "then it is over" is precisely the property the latched button could not
// express.
//
// UI[0] = (envelope, last_trigger, fire_count, magic)
#include "layout.hlsli"
#include "../_shared/ui/sui3_events.hlsli"

RWStructuredBuffer<float4> UI : register(u0);

static const float MC_MAGIC = 4242.0;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 s = UI[0];

    // Magic sentinel, not a zero test: a persistent buffer is not documented as
    // zero-initialised, and stale memory that skips the seed leaves the console
    // with a phantom envelope it never decays out of.
    if (abs(s.w - MC_MAGIC) > 0.5 || isnan(s.x)) s = float4(0.0, 0.0, 0.0, MC_MAGIC);

    // Decay first, so a fire this frame lands on a clean envelope.
    // Scaled by _DeltaTime because cook rate is not display rate.
    float dt = min(_DeltaTime, 0.05);
    s.x = saturate(s.x - dt / max(burst_decay, 0.05));

    bool fire = false;

    // RISING EDGE on the trigger parameter. Comparing against the last-seen
    // value rather than reading a level is what makes this a one-shot: holding
    // the bool true fires exactly once, which is the behaviour `type: button`
    // failed to deliver.
    float trig = burst_trigger > 0.5 ? 1.0 : 0.0;
    if (trig > 0.5 && s.y < 0.5) fire = true;
    s.y = trig;

    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        // Click only. A drag across the plate must not machine-gun the envelope.
        if (!(e.type == 5u && e.code == 1u)) continue;
        if (!mcHit(saturate(e.position), MC_RECT_BURST)) continue;
        fire = true;
    }

    if (fire) { s.x = 1.0; s.z += 1.0; }

    UI[0] = s;
}
