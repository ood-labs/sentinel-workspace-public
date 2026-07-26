// CRYOGRAM / RELIEF — combined world-height field.
//
// Bulges are composited HERE, once per texel, not inside the raymarch loop.
// Summing 16 pulses across ~130 march steps per pixel would have multiplied the
// marcher's cost by an order of magnitude; folding them into the height texture
// first leaves the march exactly as cheap as it was.
//
// Output (RGBA16F):
//   .r = solid fraction (carried through)
//   .g = FINAL world height, already scaled — downstream must NOT rescale
//   .b = orientation
//   .a = grain id

#include "common.hlsli"

struct Pulse {
    float2 center;
    float birth;
    float strength;
    float seed;
    float active;
    float2 pad;
};

StructuredBuffer<Pulse> Pulses : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

static const uint MAXPULSE = 16u;

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    float4 f = _Tex0.Load(int3(id.xy, 0));
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;

    float elev = f.g * height_scale;

    // ---- ground swells -----------------------------------------------------
    float bulge = 0.0;
    [loop] for (uint i = 0u; i < MAXPULSE; ++i) {
        Pulse p = Pulses[i];
        if (p.active < 0.5) continue;

        float age = _Time - p.birth;
        if (age < 0.0 || age > pulse_life) continue;

        // world-space offset so the swell is circular on the plate, not an
        // ellipse stretched by the 16:9 field
        float2 d = float2((uv.x - p.center.x) * 2.0 * CRYO_ASPECT,
                          (uv.y - p.center.y) * 2.0);
        float dist = length(d);

        float rad = pulse_radius + age * pulse_speed;
        if (dist > rad) continue;

        float env = exp(-age / max(pulse_decay, 0.02));
        float dome = 1.0 - smoothstep(rad * pulse_core, rad, dist);
        dome = dome * dome * (3.0 - 2.0 * dome);           // smootherstep shoulder

        // optional travelling ridge riding the leading edge
        float ring = exp(-pow((dist - rad * 0.82) / max(rad * 0.16, 1e-3), 2.0));

        bulge += p.strength * env * lerp(dome, ring, saturate(pulse_ring));
    }

    OutputUAV[id.xy] = float4(f.r, elev + bulge * pulse_amp, f.b, f.a);
}
