// Motion Console - four semantic lanes.
//
// Preserved from v1: the four lanes are Prompt / Energy / Camera / Pulse, named
// for what they drive rather than numbered. README.md:20 records why, and that
// lesson is not being relitigated.
//
// Changed from v1: burst is an ENVELOPE, not a clamp. `if (burst) lfo4 = 1.0`
// pinned the lane and the energy readout to 1.0 forever, which is how a latched
// button presents. The envelope adds to the lane and decays away, so the lane
// returns to its cycling range on its own -- the "and RELEASES" half of 3C's
// criterion 2.
struct LFOData {
    float lfo1, lfo2, lfo3, lfo4;
    float bias_x, bias_y;
    float energy, pulse;
};

RWStructuredBuffer<LFOData> Out : register(u0);
StructuredBuffer<float4>    UI  : register(t0);

static const float TWO_PI = 6.28318530718;

float evalLFO(float t, float speed, float amplitude, float shapeValue) {
    float phase = t * speed;
    float p = frac(phase);
    uint shape = (uint)clamp(round(shapeValue), 0.0, 3.0);
    float raw = shape == 0u ? sin(phase * TWO_PI) * 0.5 + 0.5
              : shape == 1u ? 1.0 - abs(p * 2.0 - 1.0)
              : shape == 2u ? p
              :               step(0.5, p);
    return saturate(raw * amplitude);
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    float t = _Time * master_rate;
    float env = saturate(UI[0].x);

    LFOData d;
    d.lfo1 = evalLFO(t, lfo1_speed, lfo1_amp, lfo1_shape);
    d.lfo2 = evalLFO(t, lfo2_speed, lfo2_amp, lfo2_shape);
    d.lfo3 = evalLFO(t, lfo3_speed, lfo3_amp, lfo3_shape);
    d.lfo4 = evalLFO(t, lfo4_speed, lfo4_amp, lfo4_shape);

    // Additive and saturating, so a fired burst reads as a transient ON TOP of
    // the lane rather than replacing it. When env reaches 0 the lane is exactly
    // what it would have been untouched.
    d.lfo4 = saturate(d.lfo4 + env);

    if (mute) { d.lfo1 = d.lfo2 = d.lfo3 = d.lfo4 = 0.0; }

    d.bias_x = saturate(motion_bias.x);
    // Y flipped exactly once, here at publish. Host xypad stores down = more
    // (3A measured pad_y 0.05 -> row 69, 0.95 -> row 94); what LEAVES this node
    // means up = more. The renderer draws the raw value so the reticle stays
    // under the pointer.
    d.bias_y = saturate(1.0 - motion_bias.y);

    d.energy = (d.lfo1 + d.lfo2 + d.lfo3 + d.lfo4) * 0.25;
    d.pulse  = d.lfo4;
    Out[0] = d;
}
