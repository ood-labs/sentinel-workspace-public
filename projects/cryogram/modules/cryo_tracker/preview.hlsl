// CRYOGRAM / MEASUREMENT — the tracker's own readout.
//
// This is not decoration. It is the only place the association logic can be
// judged: whether identities persist, where they drift, which ones the
// instrument actually believes. Encoded per track:
//
//   ring radius   -> confidence
//   colour        -> gray = provisional, AMBER = confirmed (warmth means the
//                    machine is sure; this is the piece's one accent rule)
//   arc sweep     -> age, wrapping every age_wrap seconds
//   vector        -> smoothed velocity
//   digits        -> stable track id, drawn only for confirmed tracks

#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"

struct Track {
    float2 position;
    float2 velocity;
    float age;
    float confidence;
    float id;
    float active;
};

StructuredBuffer<Track> Tracks : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const uint MAXT = 96u;
static const float3 CRYO_INK = float3(0.93, 0.93, 0.94);
static const float3 CRYO_DIM = float3(0.34, 0.34, 0.37);
static const float3 CRYO_AMBER = float3(1.00, 0.66, 0.22);
static const float TAU = 6.28318530718;

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    SuiContext c = suiContext(id.xy, _Resolution.xy);
    SuiTextStyle st = suiTextStyleTracked(1.5, 0.0, -1.5);
    float2 P = c.pixel;

    float3 col = float3(0.006, 0.006, 0.007);

    // ---- instrument field --------------------------------------------------
    float4 fr = float4(22.0, 22.0, _Resolution.x - 22.0, _Resolution.y - 22.0) /
                float4(_Resolution.xy, _Resolution.xy);
    suiComposite(col, float3(0.10, 0.10, 0.11), suiGridPx(c, 60.0, 1.0) * 0.55);
    suiComposite(col, CRYO_DIM, suiStrokeRect(c, fr, 1.0) * 0.7);

    Track hdr = Tracks[MAXT];
    int activeN = (int)hdr.velocity.x;
    int confN = (int)hdr.confidence;

    // ---- tracks ------------------------------------------------------------
    [loop] for (uint i = 0u; i < MAXT; ++i) {
        Track t = Tracks[i];
        if (t.active < 0.5) continue;

        float2 tp = t.position * _Resolution.xy;
        float2 vpx = t.velocity * _Resolution.xy * vector_gain;
        float vlen = length(vpx);
        if (vlen > 160.0) vpx *= 160.0 / vlen;

        // cheap reject: outside this track's whole footprint
        float reach = 46.0 + length(vpx) + marker_scale * 22.0;
        if (distance(P, tp) > reach) continue;

        bool confirmed = t.confidence >= confirm_threshold;
        float3 ink = confirmed ? CRYO_AMBER : CRYO_DIM;
        float alpha = confirmed ? 1.0 : (0.35 + 0.5 * t.confidence);

        float2 uvT = t.position;
        float rad = (4.0 + 9.0 * saturate(t.confidence)) * marker_scale;

        // confidence ring
        suiComposite(col, ink, suiRingPx(c, uvT, rad, 1.25) * alpha);

        // centre cross
        float2 e = float2(4.0, 0.0) * marker_scale * c.invResolution;
        float2 f = float2(0.0, 4.0) * marker_scale * c.invResolution;
        suiComposite(col, ink, suiLinePx(c, uvT - e, uvT + e, 1.0) * alpha);
        suiComposite(col, ink, suiLinePx(c, uvT - f, uvT + f, 1.0) * alpha);

        // age arc: sweep of a ring just outside the confidence ring
        float sweep = frac(t.age / max(age_wrap, 0.5));
        float2 d = P - tp;
        float ang = frac((atan2(d.y, d.x) + 3.14159265) / TAU);
        float ar = rad + 5.0 * marker_scale;
        float arcBand = 1.0 - smoothstep(1.1, 2.2, abs(length(d) - ar));
        if (ang <= sweep) suiComposite(col, ink, arcBand * 0.85 * alpha);

        // velocity vector
        if (vlen > 1.0) {
            float2 tipUv = uvT + vpx * c.invResolution;
            suiComposite(col, ink, suiLinePx(c, uvT, tipUv, 1.0) * alpha * 0.9);
            suiComposite(col, ink, suiDiscPx(c, tipUv, 1.8 * marker_scale) * alpha);
        }

        // stable identity, only where the instrument is confident
        if (confirmed && show_ids > 0.5) {
            float2 lblUv = uvT + float2(rad + 5.0, -rad - 10.0) * c.invResolution;
            suiComposite(col, CRYO_AMBER, suiInteger(c, lblUv, st, (int)t.id, 3) * 0.95);
        }
    }

    // ---- header readout ----------------------------------------------------
    float2 hAt = float2(30.0, 30.0) * c.invResolution;
    suiComposite(col, CRYO_DIM, suiInteger(c, hAt, st, activeN, 3));
    suiComposite(col, CRYO_DIM, suiGlyph(c, hAt + float2(3.0 * 7.5 + 6.0, 0.0) * c.invResolution, st, 47)); // '/'
    suiComposite(col, CRYO_AMBER, suiInteger(c, hAt + float2(4.0 * 7.5 + 10.0, 0.0) * c.invResolution, st, confN, 3));

    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
