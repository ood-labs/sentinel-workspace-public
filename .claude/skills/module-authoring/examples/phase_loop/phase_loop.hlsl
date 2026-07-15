// Phase Loop Demo - a simple seamless geometric loop for testing phase
// scrubbing and free-run playback.
//
// The whole animation is a function of a normalized loop position `u` in [0,1):
//   u = frac(phase + _Time * animation_speed * 0.2)
// - animation_speed == 0  -> u == phase, so sweeping phase 0->1 scrubs one full
//   deterministic loop (used by SWEEP_RECORD for motion eval).
// - animation_speed  > 0  -> the loop free-runs on _Time; phase becomes an offset.
//
// Builtins (_Resolution float2, _Time float) and the manifest parameters
// (phase, animation_speed, hue, brightness) are injected by the module compiler.

RWTexture2D<float4> OutputUAV : register(u0);

static const float PI  = 3.14159265;
static const float TAU = 6.28318530;

float3 hsv2rgb(float3 c) {
    float3 p = abs(frac(c.xxx + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * lerp(float3(1, 1, 1), saturate(p - 1.0), c.y);
}

// Distance from point p to the segment a-b.
float segDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 dtid : SV_DispatchThreadID) {
    if (dtid.x >= (uint)_Resolution.x || dtid.y >= (uint)_Resolution.y) return;

    float2 res = _Resolution;
    // Aspect-correct coords centered at 0, y up, y in [-0.5, 0.5].
    float2 frag = float2(dtid.xy) + 0.5;
    float2 p = (frag - 0.5 * res) / res.y;
    p.y = -p.y;

    // Normalized loop position. frac() makes the wrap (and the seam) explicit.
    float u   = frac(phase + _Time * animation_speed * 0.2);
    float ang = u * TAU;  // one full revolution per loop -> seamless at the wrap

    const float R     = 0.30;    // ring radius
    const float lineW = 0.006;   // stroke half-width

    float3 tint   = hsv2rgb(float3(hue, 0.70, 1.0));
    float3 tintHi = hsv2rgb(float3(frac(hue + 0.5), 0.45, 1.0));
    float3 col    = float3(0, 0, 0);

    // Background vignette.
    col += tint * 0.03 * smoothstep(0.95, 0.20, length(p));

    // Base ring (dim reference circle).
    float dRing = abs(length(p) - R);
    float ringMask = smoothstep(lineW * 2.0, 0.0, dRing);
    col += tint * 0.18 * ringMask;

    // Progress arc: bright over [0, u] of the ring, snaps back at the wrap.
    float pa01 = frac(atan2(p.y, p.x) / TAU);  // pixel angle in [0,1)
    col += tint * 1.0 * step(pa01, u) * ringMask;

    // Center hand pointing at the lead.
    float2 tip = R * float2(cos(ang), sin(ang));
    col += tintHi * 0.9 * smoothstep(lineW * 1.6, 0.0, segDist(p, float2(0, 0), tip));

    // Lead dot riding the arc tip.
    col += tintHi * 1.4 * smoothstep(0.020, 0.0, length(p - tip));

    // Three satellite dots orbiting at a smaller radius (makes spin direction obvious).
    [unroll] for (int i = 0; i < 3; ++i) {
        float a2 = ang + (float)i * (TAU / 3.0);
        float2 sp = (R * 0.62) * float2(cos(a2), sin(a2));
        col += tint * 0.9 * smoothstep(0.013, 0.0, length(p - sp));
    }

    // Center dot.
    col += tint * 0.5 * smoothstep(0.012, 0.0, length(p));

    col *= brightness;
    OutputUAV[dtid.xy] = float4(saturate(col), 1.0);
}
