// Bloom - a guilloche rosette: rings of rose curves, the pattern an engine-turning lathe cuts into a
// banknote, drawn as fine ink lines on paper. Six parameters shape it; in the lab each one rides an
// output of the Patch Bay through an expression, so every cable there has a face here:
//   petals  how many lobes, 3..12 - a whole count most of the way between two counts, and across the
//           middle fifth a morph from one to the other, so a count that moves never tears the ring
//   depth   how deep the notches between the lobes cut: 0 a circle, 1 to the centre
//   twist   how far each ring turns past the one inside it: the spiral arms, and the weave
//   spin    the whole rosette's turn (turns)
//   size    the outer radius, a fraction of the half height
//   hue     the ink's hue (OKLCH degrees; lightness and chroma stay put, so only the hue moves)
// Two families of rings turn opposite ways and cross into the lattice that makes guilloche read as
// woven; at zero twist they interlace half a lobe apart.
#define IL_TYPE_TEX _Tex0
#include "_labels.generated.hlsli"           // before il_text: it turns on the label functions
#include "../_shared/ui/il_text.hlsli"
#include "../_shared/palette.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

#define RINGS_MAX 32
#define TAU 6.2831853

static float g_n0, g_n1, g_f, g_depth;

// the rose at angle a for a unit radius: (radius, d radius / d a). The lobe profile is a raised
// cosine, 1 at a tip and 0 in a notch; a fractional count blends the two whole counts around it.
float2 rose(float a)
{
    float w = lerp(0.5 + 0.5 * cos(g_n0 * a), 0.5 + 0.5 * cos(g_n1 * a), g_f);
    float dw = lerp(-0.5 * g_n0 * sin(g_n0 * a), -0.5 * g_n1 * sin(g_n1 * a), g_f);
    return float2(1.0 - g_depth * (1.0 - w), g_depth * dw);
}

// signed distance in px from a polar point to one ring (radius r0 units, turned by phi)
float ringDist(float rho, float th, float r0, float phi, float unit)
{
    float2 rr = rose(th - phi) * r0;
    return (rho - rr.x) * unit / sqrt(1.0 + rr.y * rr.y / max(rho * rho, 1e-4));
}

float3 ink(float L, float C, float h)
{
    bool clipped;
    return palToDisplay(palGamutMap(palLchToLab(float3(L, C, h)), clipped));
}

[numthreads(16, 16, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (id.x >= W || id.y >= H) return;
    float2 res = float2(W, H);
    float2 p = float2(id.xy) + 0.5;
    float k = res.y / 720.0;                               // type and line scale
    float unit = 0.5 * res.y;                              // px per unit radius
    float2 q = (p - 0.5 * res) / unit;
    float rho = length(q);
    float th = atan2(q.x, -q.y);                           // clockwise from twelve o'clock

    float n = clamp(petals, 3.0, 12.0);
    g_n0 = floor(n);
    g_n1 = g_n0 + 1.0;
    g_f = smoothstep(0.4, 0.6, n - g_n0);                // whole counts most of the way, a quick morph between
    g_depth = saturate(depth);
    float R = clamp(size, 0.1, 0.95);
    float lobe = TAU / n;                                  // one lobe's angle
    float turn = spin * TAU;
    float sweep = clamp(twist, -1.0, 1.0) * 1.5 * lobe;    // the outer ring turns this far past the inner
    uint K = (uint)clamp(rings, 4, RINGS_MAX);

    float3 paper = float3(0.936, 0.930, 0.914);
    float3 inkA = ink(0.40, 0.14, hue);
    float3 inkB = ink(0.62, 0.10, hue + 35.0);
    float3 wash = ink(0.955, 0.03, hue);
    float3 col = paper;

    // the silhouette, washed: inside the outermost ring of the first family
    float dOut = ringDist(rho, th, R, turn + sweep, unit);
    col = lerp(col, wash, saturate(0.5 - dOut));

    // the rings: the second family under the first, each a hairline
    float lw = 1.15 * k;
    float covA = 0.0, covB = 0.0;
    [loop] for (uint i = 0u; i < K; i++)
    {
        float t = ((float)i + 1.0) / (float)K;
        float r0 = R * lerp(0.12, 1.0, t);
        // cheap reject: the ring lies between (1 - depth) r0 and r0
        if (rho > r0 + 4.0 / unit || rho < r0 * (1.0 - g_depth) - 4.0 / unit) continue;
        float dA = ringDist(rho, th, r0, turn + sweep * t, unit);
        float dB = ringDist(rho, th, r0, turn - sweep * t + 0.5 * lobe, unit);
        covA = max(covA, saturate(0.5 * lw + 0.5 - abs(dA)));
        covB = max(covB, saturate(0.5 * lw + 0.5 - abs(dB)));
    }
    col = lerp(col, inkB, covB * 0.85);
    col = lerp(col, inkA, covA);

    // the readout: what the six inputs are right now
    if (readout && p.x < 200.0 * k && p.y > res.y - 150.0 * k)
    {
        float3 tx = float3(0.17, 0.17, 0.18);
        float x0 = 28.0 * k, x1 = 150.0 * k, sz = 11.5 * k;
        float y = res.y - 130.0 * k;
        float c = ilLabel(p, x0, y, 10.5 * k, LB_INPUTS, IL_LEFT) * 0.7;
        static const uint LBS[6] = { LB_PETALS, LB_DEPTH, LB_TWIST, LB_SPIN, LB_SIZE, LB_HUE };
        float vals[6] = { n, g_depth, clamp(twist, -1.0, 1.0), spin, R, hue };
        [unroll] for (uint r = 0u; r < 6u; r++)
        {
            float yr = y + (r + 1.0) * 17.0 * k;
            c = max(c, ilLabel(p, x0, yr, sz, LBS[r], IL_LEFT) * 0.75);
            c = max(c, r == 2u ? ilNumSigned(p, x1, yr, sz, vals[r], 2, IL_RIGHT)
                               : ilNum(p, x1, yr, sz, vals[r], r == 5u ? 0 : 2, IL_RIGHT));
        }
        col = lerp(col, tx, c);
    }
    OutputUAV[id.xy] = float4(col, 1.0);
}
