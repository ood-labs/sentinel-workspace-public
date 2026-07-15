// cutout_common — shared record layouts + per-copy drift/scale math for face_cutout.
// Included by compute.hlsl (writes the Clones buffer) and cutout.hlsl (draws from it) so the
// rendered stamps and the published buffer are guaranteed identical. Injected params
// (motion_mode, drift_speed, drift_range, scale_mode, scale_amt, scale_speed, scale_independent,
// copies, copy_spread, stamp_scale, sample_scale) + _Time/_Resolution are in scope in each pass.
#ifndef CUTOUT_COMMON
#define CUTOUT_COMMON

static const uint  MAX_NODES  = 16;
static const uint  MAX_COPIES = 16;
static const float TAU = 6.2831853;

// ring-buffer delay line of recent face frames + anchor UVs (a copy delayed by k*delay_time seconds
// samples the face AND its tracking UV from that moment, interpolated between captured frames).
// element_count in manifest MUST equal HW*HH*HF (face ring) and HF*MAX_NODES (anchor ring).
static const uint  HW = 256;
static const uint  HH = 448;
static const uint  HF = 48;

// ring time (float) of the delayed sample for copy `copyIdx`, clamped inside the valid ring window.
float ringTimeFor(uint copyIdx)
{
    float head_f = _Time * capture_rate;
    float age = (float)copyIdx * delay_time * capture_rate;
    float lo = max(head_f - (float)(HF - 1u), 0.0);
    return clamp(head_f - age, lo, head_f);
}

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight;
    float group; float kind; float seed; float active;
};

// 56 B — one drifting/scaled duplicate of a feature
struct Clone {
    float2 pos;   // NDC centre
    float2 ext;   // NDC half-extents (after animated scale)
    float2 uv;    // feature sample centre (image uv)
    float2 win;   // sample-window half size (uv)
    float2 vel;   // NDC displacement over ~1 frame (for overlay lead/latency correction)
    float  group; // eye / mouth / nose ...
    float  kind;
    float  seed;
    float  active;
};

float hash21(float2 p){ p = frac(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return frac(p.x * p.y); }
float2 hash22(float2 p){ return float2(hash21(p), hash21(p + 7.13)); }
float vnoise(float2 p){
    float2 i = floor(p), f = frac(p);
    float a = hash21(i), b = hash21(i + float2(1,0)), c = hash21(i + float2(0,1)), d = hash21(i + float2(1,1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}
float fbm(float2 p){ float s = 0.0, a = 0.5; [unroll] for (int i = 0; i < 4; i++){ s += a * vnoise(p); p *= 2.02; a *= 0.5; } return s; }

float2 driftAt(float sd, float t)
{
    int mode = (int)motion_mode;
    if (mode == 1) {                                 // Noise
        float ts = t * drift_speed * 0.25;
        return float2(fbm(float2(ts,        sd * 5.0 +  2.0)) * 2.0 - 1.0,
                      fbm(float2(ts + 41.0, sd * 5.0 + 23.0)) * 2.0 - 1.0);
    } else if (mode == 2) {                          // Spiral
        float rate = drift_speed * (0.5 + hash21(float2(sd, 1.0)) * 1.5);
        float ph = hash21(float2(sd, 3.0)) * TAU;
        float rad = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * drift_speed * 0.4 + hash21(float2(sd, 5.0)) * TAU));
        return float2(cos(t * rate + ph), sin(t * rate + ph)) * rad;
    } else if (mode == 3) {                          // Wave
        float rate = drift_speed * (0.6 + hash21(float2(sd, 2.0)) * 1.2);
        float ph = hash21(float2(sd, 4.0)) * TAU;
        return float2(0.35 * sin(t * rate * 0.6 + ph), sin(t * rate + ph));
    } else if (mode == 4) {                          // Static
        return hash22(float2(sd, 9.0)) * 2.0 - 1.0;
    }
    float rx = drift_speed * (0.4 + hash21(float2(sd, 1.0)) * 1.6);   // Orbit
    float ry = drift_speed * (0.4 + hash21(float2(sd, 2.0)) * 1.6);
    float px = hash21(float2(sd, 3.0)) * TAU;
    float py = hash21(float2(sd, 4.0)) * TAU;
    return float2(cos(t * rx + px), sin(t * ry + py));
}
float2 driftFn(float sd){ return driftAt(sd, _Time); }

float scaleWave(float sd)
{
    int sm = (int)scale_mode;
    if (sm == 1) return sin(_Time * scale_speed + hash21(float2(sd, 30.0)) * TAU);
    if (sm == 2) return fbm(float2(_Time * scale_speed * 0.3, sd * 3.0 + 60.0)) * 2.0 - 1.0;
    return 0.0;
}

// the shared per-copy transform — one source of truth for both passes
Clone makeClone(PNode n, uint copyIdx, bool live)
{
    Clone c;
    c.pos = 0; c.ext = 0; c.uv = 0; c.win = 0; c.vel = 0;
    c.group = n.group; c.kind = n.kind; c.seed = 0; c.active = 0;
    if (!live) return c;

    float sd = n.seed + (float)copyIdx * 13.71;
    float outAspect = _Resolution.x / max(1.0, _Resolution.y);
    float2 aspect = float2(1.0 / outAspect, 1.0);
    float hw = max(0.03, n.weight) * stamp_scale;

    float2 baseOff = (hash22(float2(sd, 17.0)) - 0.5) * copy_spread;
    float2 drawCenter = n.pos + baseOff + driftAt(sd, _Time) * drift_range;
    float2 nextCenter = n.pos + baseOff + driftAt(sd, _Time + 0.016) * drift_range;

    float sx = 1.0 + scale_amt * scaleWave(sd);
    float sy = scale_independent ? (1.0 + scale_amt * scaleWave(sd + 100.0)) : sx;
    sx = max(0.05, sx); sy = max(0.05, sy);

    c.pos = drawCenter;
    c.vel = nextCenter - drawCenter;               // ~1 frame of drift
    c.ext = float2(aspect.x * hw * sx, hw * sy);
    c.uv  = float2(n.pos.x * 0.5 + 0.5, 0.5 - n.pos.y * 0.5);
    c.win = float2(hw * aspect.x, hw) * sample_scale;
    c.seed = sd;
    c.active = 1.0;
    return c;
}

#endif
