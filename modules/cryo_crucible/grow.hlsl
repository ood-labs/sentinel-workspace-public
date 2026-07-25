// CRYOGRAM / SPECIMEN — anisotropic solidification field.
//
// Continuous-fraction cellular growth. Liquid cells accumulate solid fraction
// from solid neighbours; the accumulation rate is shaped by an n-fold
// anisotropy kernel evaluated against the DONOR cell's crystallographic
// orientation, so fronts facet instead of blobbing. Orientation and grain id
// are locked at first contact, which makes grains coherent regions with hard
// boundaries at their meeting lines — exactly the structure the measurement
// layer downstream is built to detect.
//
// State buffer (RGBA32F, persistent):
//   .r = solid fraction s   (0 = liquid, >=1 = solid)
//   .g = orientation theta  (radians)
//   .b = grain id           (0 = none, else hashed 0.02..0.98)
//   .a = age                (seconds since the cell first solidified)
//
// Life cycle: nucleate -> grow -> hold -> resorb (age > anneal_life) -> liquid.
// Growth and resorption are mutually exclusive, so a dissolving grain cannot be
// re-fed by its own front. Every rate is per SECOND and scaled by _DeltaTime;
// modules cook far above display rate, so a per-cook constant would run away.

RWTexture2D<float4> OutputUAV : register(u0);

// Probes live INSIDE this module. A console node downstream cannot feed them
// back in — that would be a graph cycle — so the specimen owns its own authored
// marks and publishes them outward instead.
struct Probe {
    float2 pos;
    float radius;
    float strength;
    float kind;
    float age;
    float id;
    float active;
};
StructuredBuffer<Probe> Probes : register(t1);

static const float TAU = 6.28318530718;

// Integer bit-mix hash. The injected sin-based hash21 collapses toward zero for
// large arguments (pixel coords + a time counter), which detonated nucleation.
uint cryoHashU(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return v.x;
}

float cryoRand(uint2 p, uint seed) {
    return (float)(cryoHashU(uint3(p, seed)) & 0x00FFFFFFu) * (1.0 / 16777216.0);
}

float symmetryFold() {
    if (symmetry < 0.5) return 3.0;
    if (symmetry < 1.5) return 4.0;
    if (symmetry < 2.5) return 6.0;
    return 8.0;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;
    int2 px = int2(id.xy);

    float dt = clamp(_DeltaTime, 0.0, 0.0333);

    float4 st = _Tex0.Load(int3(px, 0));
    float s   = st.r;
    float th  = st.g;
    float gid = st.b;
    float age = st.a;

    if (reset > 0.5) {
        OutputUAV[id.xy] = float4(0.0, 0.0, 0.0, 0.0);
        return;
    }

    // Age advances for anything that has ever been part of a grain.
    if (gid > 0.0) age += dt;

    // ---- authored probes: the loop closing back on the specimen -----------
    // SEED attracts growth toward itself and raises nucleation.
    // ANNEAL forces resorption. ANCHOR protects material from its own age.
    float aspect = _Resolution.x / _Resolution.y;
    float2 cuv = (float2(px) + 0.5) / _Resolution.xy;

    float seedBias = 0.0, annealForce = 0.0, anchorForce = 0.0, attractW = 0.0;
    float2 attractVec = float2(0.0, 0.0);

    [loop] for (uint pi = 0u; pi < 32u; ++pi) {
        Probe pb = Probes[pi];
        if (pb.active < 0.5) continue;
        float rr = max(pb.radius, 1e-3);
        // probe circles are drawn circular in PIXELS on a 16:9 preview, so the
        // uv-space falloff has to be de-aspected or the influence is an ellipse
        float2 d = (cuv - pb.pos) * float2(1.0, 1.0 / aspect);
        float f = exp(-dot(d, d) / (rr * rr * 0.5));
        if (f < 0.002) continue;

        float k = pb.kind;
        if (k < 0.5) {
            seedBias += f * probe_seed_gain;
            attractVec += (pb.pos - cuv) * f;
            attractW += f;
        } else if (k < 1.5) {
            annealForce = max(annealForce, f);
        } else {
            anchorForce = max(anchorForce, f);
        }
    }

    if (anchorForce > 0.35) age = min(age, anneal_life * 0.92);   // protected

    if (annealForce > 0.03 && s > 0.0) {
        s -= probe_anneal_rate * annealForce * dt;
        if (s <= 0.0) { s = 0.0; th = 0.0; gid = 0.0; age = 0.0; }
        OutputUAV[id.xy] = float4(s, th, gid, age);
        return;
    }

    float attractAng = atan2(attractVec.y, attractVec.x);
    float attractAmt = probe_attract * saturate(attractW);

    // Anchoring is evaluated BEFORE the resorption test, otherwise a protected
    // cell would already have returned as resorbing and the probe would do
    // nothing to the material it is supposed to be holding.
    bool resorbing = (gid > 0.0) && (age > anneal_life);
    if (resorbing) {
        s -= anneal_rate * dt;
        if (s <= 0.0) { s = 0.0; th = 0.0; gid = 0.0; age = 0.0; }
        OutputUAV[id.xy] = float4(s, th, gid, age);
        return;
    }

    float fold = symmetryFold();
    float sharp = max(facet_sharpness, 1.0);

    // Smooth spatial perturbation of the facet direction. Evaluated ONCE per
    // cell and applied to the kernel only — never stored — so dendrites curve
    // organically while each grain keeps a single exact crystallographic axis.
    float wob = (fbm2D(float2(px) * 0.0037, 3) - 0.5) * facet_wobble;

    // ---- gather anisotropic growth propensity from solid neighbours --------
    float accum = 0.0;
    float bestW = 0.0;
    float bestTh = 0.0;
    float bestId = 0.0;

    [unroll] for (int dy = -1; dy <= 1; ++dy) {
        [unroll] for (int dx = -1; dx <= 1; ++dx) {
            if (dx == 0 && dy == 0) continue;
            int2 q = clamp(px + int2(dx, dy), int2(0, 0), int2(res) - 1);
            float4 n = _Tex0.Load(int3(q, 0));
            if (n.r < 0.999) continue;
            if (n.b <= 0.0) continue;
            if (n.a > anneal_life) continue;   // a resorbing cell donates nothing

            float2 dir = float2((float)dx, (float)dy);
            float len = length(dir);
            float phi = atan2(dir.y, dir.x);

            float lobe = 0.5 + 0.5 * cos(fold * (phi - n.g + wob));
            float aniso = pow(saturate(lobe), sharp);
            aniso = lerp(1.0, aniso, saturate(facet_bias));

            // SEED attraction: fronts advancing toward a probe gain propensity,
            // so grains visibly reach for it instead of merely nucleating near it.
            float pull = 1.0 + attractAmt * saturate(cos(phi - attractAng));

            float w = aniso * pull / len;
            accum += w;
            if (w > bestW) { bestW = w; bestTh = n.g; bestId = n.b; }
        }
    }

    // ---- growth (growth_rate is a front speed in pixels/second) ------------
    if (s < 0.999 && accum > 0.0) {
        if (gid <= 0.0) {
            // Orientation is inherited EXACTLY. Any per-cell jitter here random
            // walks across the grain and decorrelates the hatch into static.
            th = bestTh;
            gid = bestId;
            age = 0.0;
        }
        float nz = 0.75 + 0.50 * cryoRand((uint2)px, (uint)(_Time * 90.0) * 2654435761u + 13u);
        s += saturate(accum / 1.5) * growth_rate * nz * dt;
        s = min(s, 1.0);
    }

    // ---- spontaneous nucleation -------------------------------------------
    if (s <= 0.0001 && gid <= 0.0) {
        float2 c = (float2(px) + 0.5) / _Resolution.xy;
        float2 d = (c - bias_center) * float2(_Resolution.x / _Resolution.y, 1.0);
        float bias = 1.0 + bias_gain * exp(-dot(d, d) * 26.0);

        uint seed = (uint)(_Time * 120.0) * 747796405u + 2891336453u;
        float r = cryoRand((uint2)px, seed);
        float p = nucleation_rate * bias * (1.0 + seedBias) * dt * 1.0e-6;
        if (r < p) {
            s = 1.0;
            th = cryoRand((uint2)px, seed ^ 0x9E3779B9u) * TAU;
            gid = 0.02 + 0.96 * cryoRand((uint2)px, seed ^ 0x85EBCA6Bu);
            age = 0.0;
        }
    }

    OutputUAV[id.xy] = float4(s, th, gid, age);
}
