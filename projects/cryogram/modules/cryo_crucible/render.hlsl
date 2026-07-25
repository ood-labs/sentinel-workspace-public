// CRYOGRAM / SPECIMEN — microscope read of the solidification field.
//
// Strictly monochrome. This is the raw specimen; the warm accent is reserved
// for the measurement layer, where it means "the instrument is confident".
//
// Encoded here:
//   grain interior    -> per-grain shade + orientation hatching (gives the
//                        Features line task real, meaningful line content)
//   grain boundary    -> bright hairline where grain id changes; triple
//                        junctions therefore become genuine corner records
//   growth front      -> brightest band, advancing material
//   resorption front  -> dark stippled band, material being lost
//   liquid            -> near-black with faint concentration grain

RWTexture2D<float4> OutputUAV : register(u0);

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

#include "shock.hlsli"
StructuredBuffer<Shock> Shocks : register(t2);
#include "shock_apply.hlsli"

static const float3 PROBE_SEED   = float3(1.00, 0.66, 0.22);
static const float3 PROBE_ANNEAL = float3(0.88, 0.28, 0.24);
static const float3 PROBE_ANCHOR = float3(0.94, 0.94, 0.96);

float4 loadState(int2 p, uint2 res) {
    return _Tex0.Load(int3(clamp(p, int2(0, 0), int2(res) - 1), 0));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    int2 px = int2(id.xy);

    float4 st = loadState(px, res);
    float s = st.r, th = st.g, gid = st.b, age = st.a;
    bool solid = s >= 0.999;
    bool resorbing = (gid > 0.0) && (age > anneal_life);

    // ---- liquid bed --------------------------------------------------------
    float bed = liquid_level * (0.45 + 0.85 * fbm2D(float2(px) * 0.0135 +
                                float2(_Time * 0.021, -_Time * 0.017), 3));
    float lum = bed;

    // ---- grain interior ----------------------------------------------------
    if (solid) {
        float shade = 0.42 + 0.58 * frac(gid * 7.317);
        float base = interior_level * shade;

        // Lamellar twinning: a deterministic fraction of grains carry alternating
        // bands whose hatch axis is mirrored about the grain axis. Real
        // crystallography, and it gives the Features line task two competing
        // line families inside a single region instead of one.
        float thUse = th;
        bool twinned = frac(gid * 23.117) < twin_fraction;
        if (twinned) {
            float2 across = float2(-sin(th), cos(th));
            float band = frac(dot(float2(px) + 0.5, across) / max(twin_pitch, 4.0));
            if (band < 0.5) thUse = th + twin_angle;
        }

        float pitch = max(hatch_pitch, 2.0);
        float h = dot(float2(px) + 0.5, float2(cos(thUse), sin(thUse)));
        float dline = abs(frac(h / pitch + 0.5) - 0.5) * pitch;
        float stroke = 1.0 - smoothstep(hatch_width, hatch_width + 1.15, dline);

        lum = base + stroke * (0.28 + 0.44 * shade);
    }

    // ---- grain boundaries --------------------------------------------------
    float bw = max(boundary_width, 0.5);
    int rad = max((int)round(bw), 1);
    float grainEdge = 0.0;
    float phaseEdge = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            if (dx == 0 && dy == 0) continue;
            float4 n = loadState(px + int2(dx, dy) * rad, res);
            bool nsolid = n.r >= 0.999;
            if (solid && nsolid && n.b > 0.0 && gid > 0.0 && abs(n.b - gid) > 0.004) grainEdge = 1.0;
            if (solid != nsolid) phaseEdge = 1.0;
        }
    }
    lum = max(lum, grainEdge * 0.94);
    lum = max(lum, phaseEdge * (resorbing ? 0.10 : 0.42));

    // ---- advancing vs. retreating material ---------------------------------
    bool partial = (s > 0.02 && s < 0.999);
    if (partial && !resorbing) {
        lum = max(lum, (0.38 + 0.62 * s) * front_gain);
    } else if (partial && resorbing) {
        // resorption reads as loss: darken, and stipple so the band is legible
        float stip = step(0.55, frac(dot(float2(px), float2(0.37, 0.29))));
        lum = min(lum, 0.05 + 0.16 * s * stip);
    }

    // ---- freshly solidified rim decays back into the plate -----------------
    if (solid && !resorbing) {
        float fresh = saturate(1.0 - age / 0.75);
        lum = max(lum, fresh * 0.90 * front_gain);
    }

    lum = saturate(lum * exposure);
    float3 col = float3(lum, lum, lum);

    // ---- authored probes, drawn where they actually act -------------------
    if (probe_overlay > 0.5) {
        float aspect = _Resolution.x / _Resolution.y;
        float2 uv = (float2(px) + 0.5) / _Resolution.xy;
        float sx = _Resolution.x;

        [loop] for (uint pi = 0u; pi < 32u; ++pi) {
            Probe pb = Probes[pi];
            if (pb.active < 0.5) continue;

            float2 d = (uv - pb.pos) * float2(1.0, 1.0 / aspect);
            float dpx = length(d) * sx;
            float rpx = pb.radius * sx;
            if (dpx > rpx + 14.0) continue;

            float3 pc = (pb.kind < 0.5) ? PROBE_SEED
                      : ((pb.kind < 1.5) ? PROBE_ANNEAL : PROBE_ANCHOR);

            float ring = 1.0 - smoothstep(0.8, 2.1, abs(dpx - rpx));
            if (pb.kind > 0.5 && pb.kind < 1.5) {
                float a = atan2(d.y, d.x);
                ring *= step(0.45, frac(a * 3.2));            // ANNEAL reads dashed
            }
            col = lerp(col, pc, ring * 0.95);

            // crosshair + a faint interior wash so the region of action is legible
            float ch = max(1.0 - smoothstep(0.6, 1.7, abs(d.x) * sx),
                           1.0 - smoothstep(0.6, 1.7, abs(d.y) * sx));
            if (dpx < 7.0) col = lerp(col, pc, ch * 0.9);
            col = lerp(col, pc, (1.0 - smoothstep(0.0, rpx, dpx)) * 0.09);
        }

        // live brush cursor
        Probe hdr = Probes[32];
        float2 cur = _ViewportPointerPosition;
        if (cur.x > 0.0 && cur.x < 1.0 && cur.y > 0.0 && cur.y < 1.0) {
            float2 dc = (uv - cur) * float2(1.0, 1.0 / aspect);
            float dcp = length(dc) * sx;
            float rc = hdr.radius * sx;
            float3 cc = (hdr.pos.y < 0.5) ? PROBE_SEED
                      : ((hdr.pos.y < 1.5) ? PROBE_ANNEAL : PROBE_ANCHOR);
            col = lerp(col, cc, (1.0 - smoothstep(0.6, 1.7, abs(dcp - rc))) * 0.5);
        }
    }

    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
