// CRYOGRAM / MEASUREMENT — the lattice's own readout.
//
//   stroke weight -> strain (compressed bonds draw heavy, stretched draw fine)
//   brightness    -> joint confidence of the two bonded identities
//   amber node    -> a confirmed identity (the accent still means exactly one
//                    thing across the whole piece: the instrument is sure)
//   bottom strip  -> live distribution of bond lengths against spacing

#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"

struct Filament {
    float2 a;
    float2 b;
    float idA;
    float idB;
    float len;
    float strain;
    float weight;
    float age;
    float2 pad;
};

StructuredBuffer<Filament> Fil : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const uint MAXE = 160u;
static const float3 CRYO_INK = float3(0.93, 0.93, 0.94);
static const float3 CRYO_DIM = float3(0.34, 0.34, 0.37);
static const float3 CRYO_AMBER = float3(1.00, 0.66, 0.22);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    SuiContext c = suiContext(id.xy, _Resolution.xy);
    SuiTextStyle st = suiTextStyleTracked(1.5, 0.0, -1.5);
    float2 P = c.pixel;

    float3 col = float3(0.006, 0.006, 0.007);
    suiComposite(col, float3(0.09, 0.09, 0.10), suiGridPx(c, 60.0, 1.0) * 0.5);

    float4 fr = float4(22.0, 22.0, _Resolution.x - 22.0, _Resolution.y - 22.0) /
                float4(_Resolution.xy, _Resolution.xy);
    suiComposite(col, CRYO_DIM, suiStrokeRect(c, fr, 1.0) * 0.65);

    Filament hdr = Fil[MAXE];
    int edgeN = (int)hdr.a.x;
    int nodeN = (int)hdr.a.y;
    float spacing = max(hdr.len, 1e-4);

    // ---- bonds -------------------------------------------------------------
    [loop] for (uint i = 0u; i < MAXE; ++i) {
        Filament f = Fil[i];
        if (f.weight <= 0.0) continue;

        float2 ap = f.a * _Resolution.xy;
        float2 bp = f.b * _Resolution.xy;

        // segment reject
        float2 ab = bp - ap;
        float h = saturate(dot(P - ap, ab) / max(dot(ab, ab), 1e-6));
        if (distance(P, ap + ab * h) > 14.0) continue;

        // compressed bonds read heavy, stretched bonds read fine
        float w = lerp(bond_weight_max, bond_weight_min, saturate(f.strain * 0.5 + 0.5));
        float bright = (0.30 + 0.70 * saturate(f.weight)) * bond_gain;

        suiComposite(col, CRYO_INK, suiLinePx(c, f.a, f.b, w) * bright);
    }

    // ---- confirmed identities ----------------------------------------------
    [loop] for (uint j = 0u; j < MAXE; ++j) {
        Filament f = Fil[j];
        if (f.weight <= 0.0) continue;
        if (distance(P, f.a * _Resolution.xy) < 12.0)
            suiComposite(col, CRYO_AMBER, suiRingPx(c, f.a, 3.4 * node_scale, 1.3));
        if (distance(P, f.b * _Resolution.xy) < 12.0)
            suiComposite(col, CRYO_AMBER, suiRingPx(c, f.b, 3.4 * node_scale, 1.3));
    }

    // ---- bond-length distribution -------------------------------------------
    float4 strip = float4(0.030, 0.905, 0.970, 0.960);
    suiComposite(col, CRYO_DIM, suiStrokeRect(c, strip, 1.0) * 0.5);
    if (c.uv.x > strip.x && c.uv.x < strip.z && c.uv.y > strip.y && c.uv.y < strip.w) {
        float t = (c.uv.x - strip.x) / (strip.z - strip.x);
        float lo = t * spacing * 3.0;
        float hi = lo + spacing * 3.0 / 64.0;
        float cnt = 0.0;
        [loop] for (uint k = 0u; k < MAXE; ++k) {
            Filament f = Fil[k];
            if (f.weight <= 0.0) continue;
            if (f.len >= lo && f.len < hi) cnt += 1.0;
        }
        float hgt = saturate(cnt / 6.0);
        float top = lerp(strip.w, strip.y, hgt);
        if (c.uv.y > top) suiComposite(col, CRYO_INK, 0.75);
    }
    // spacing marker on the distribution
    float sx = strip.x + (strip.z - strip.x) / 3.0;
    suiComposite(col, CRYO_AMBER, suiLinePx(c, float2(sx, strip.y - 0.012),
                                               float2(sx, strip.w + 0.012), 1.0) * 0.9);

    // ---- readout: nodes / bonds ---------------------------------------------
    float2 hAt = float2(30.0, 30.0) * c.invResolution;
    suiComposite(col, CRYO_AMBER, suiInteger(c, hAt, st, nodeN, 3));
    suiComposite(col, CRYO_DIM, suiGlyph(c, hAt + float2(3.0 * 7.5 + 6.0, 0.0) * c.invResolution, st, 47));
    suiComposite(col, CRYO_INK, suiInteger(c, hAt + float2(4.0 * 7.5 + 10.0, 0.0) * c.invResolution, st, edgeN, 3));

    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
