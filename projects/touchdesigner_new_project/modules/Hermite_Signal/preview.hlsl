// Full-bleed Hermite signal scope.
//
// This deliberately uses the same proven plotting primitives and Scientifica
// bitmap face as Interaction Lab's Data Scope and the audio_bands instrument:
// pixel-space geometry, snapped 1 px rules, integer glyph scale, real axis
// values, and no decorative panel surrounding the plot.
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "../_shared/ui/sui3_theme.hlsli"

struct SignalSample
{
    float sample_index;
    float sample_u;
    float value;
    float active;
};

StructuredBuffer<SignalSample> Samples : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float SIGNAL_MIN = -0.25;
static const float SIGNAL_MAX =  1.25;
static const float3 TRACE_RED  = float3(0.94, 0.16, 0.07);

float sampleX(float u, float width)
{
    // First and last records land on the first and last pixel centres. This is
    // the edge-to-edge contract; neither labels nor tick gutters shorten it.
    return 0.5 + saturate(u) * max(width - 1.0, 0.0);
}

float signalY(float value, float height)
{
    float n = saturate((value - SIGNAL_MIN) / (SIGNAL_MAX - SIGNAL_MIN));
    return 0.5 + (1.0 - n) * max(height - 1.0, 0.0);
}

// Compact fixed point used by the axes: " 0.00", " 1.25", "-0.25".
// sui3Fixed intentionally reserves two integer digits for general telemetry;
// this scope's frozen -0.25..1.25 domain only needs one, leaving the labels
// quiet enough to sit inside the raw plot.
float scopeFixed2(float2 P, float2 anchor, float s, float value)
{
    if (sui3RunMiss(P, anchor, s, 5)) return 0.0;
    float av = min(abs(value), 9.99);
    int ip = (int)floor(av);
    int fp = (int)floor(frac(av) * 100.0 + 0.5);
    if (fp >= 100) { fp = 0; ip = min(ip + 1, 9); }

    float cov = sui3Glyph(P, anchor, s, value < -0.0001 ? S_MI : S_SP);
    cov = max(cov, sui3Glyph(P, anchor + float2(1.0 * SUI3_ADVANCE * s, 0.0), s, S_0 + ip));
    cov = max(cov, sui3Glyph(P, anchor + float2(2.0 * SUI3_ADVANCE * s, 0.0), s, S_DT));
    cov = max(cov, sui3Digits(P, anchor + float2(3.0 * SUI3_ADVANCE * s, 0.0), s, fp, 2));
    return cov;
}

float sampleLabel(float2 P, float2 anchor, float s, int value)
{
    int digits = value < 10 ? 1 : value < 100 ? 2 : 3;
    return sui3Digits(P, anchor, s, value, digits);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 R = _Resolution.xy;
    if (tid.x >= (uint)R.x || tid.y >= (uint)R.y) return;

    float2 P = float2(tid.xy) + 0.5;
    float k = min(R.x / 960.0, R.y / 540.0);
    // Integer-only scaling keeps Scientifica crisp. The canonical panel now
    // uses 2x type; larger docks step to 3x and 4x instead of leaving a tiny
    // fixed-size stamp in a growing Canvas.
    float s = k >= 1.8 ? 4.0 : k >= 1.2 ? 3.0 : k >= 0.72 ? 2.0 : 1.0;
    Sui3Theme T = sui3Theme(TRACE_RED);
    float3 col = T.field;

    // Minor and major graticule. The plot is the viewport itself: there is no
    // enclosing card, inset well, border, title bar, or side instrument.
    [loop] for (int ix = 0; ix <= 16; ++ix)
    {
        float x = sampleX((float)ix / 16.0, R.x);
        float ink = sui3HairAt(P.x, x);
        col += T.rule * ink * ((ix & 1) == 0 ? 0.34 : 0.14);
    }
    [loop] for (int iy = 0; iy <= 12; ++iy)
    {
        float value = lerp(SIGNAL_MIN, SIGNAL_MAX, (float)iy / 12.0);
        float y = signalY(value, R.y);
        float ink = sui3HairAt(P.y, y);
        col += T.rule * ink * ((iy & 1) == 0 ? 0.34 : 0.14);
    }

    // Zero and midpoint references carry slightly more weight because they
    // describe the displacement signal's actual operating range.
    col += T.mid * 0.34 * sui3HairAt(P.y, signalY(0.0, R.y));
    col += T.mid * 0.48 * sui3HairAt(P.y, signalY(0.5, R.y));

    // Bounded tick rails on all four viewport edges. They are separate marks,
    // not a frame; the raw field still runs uninterrupted underneath them.
    [loop] for (int tx = 0; tx <= 8; ++tx)
    {
        float x = sampleX((float)tx / 8.0, R.x);
        float tick = sui3HairAt(P.x, x);
        col += T.dim * tick * (step(P.y, 7.0 * s) + step(R.y - 7.0 * s, P.y));
    }
    [loop] for (int ty = 0; ty <= 6; ++ty)
    {
        float value = lerp(SIGNAL_MIN, SIGNAL_MAX, (float)ty / 6.0);
        float y = signalY(value, R.y);
        float tick = sui3HairAt(P.y, y);
        col += T.dim * tick * (step(P.x, 7.0 * s) + step(R.x - 7.0 * s, P.x));
    }

    // Y values are printed just inside the field and remain attached to their
    // exact gridline. At the top and bottom the anchors move inward by one
    // glyph row so the numerals never clip.
    [loop] for (int yl = 0; yl <= 6; ++yl)
    {
        float value = lerp(SIGNAL_MIN, SIGNAL_MAX, (float)yl / 6.0);
        float y = signalY(value, R.y);
        float labelY = clamp(y - 5.5 * s, 1.0 * s, R.y - 12.0 * s);
        // The lowest Y label shares the bottom edge with the sample-index
        // axis. Lift that one label by a full row rather than allowing "-0.25"
        // and sample 0 to fuse into a false number.
        if (yl == 0) labelY = min(labelY, R.y - 24.0 * s);
        col += T.dim * 0.92 * scopeFixed2(P, float2(9.0 * s, labelY), s, value);
    }

    // Sample indices form the X axis. Labels sit inside the graph so the trace
    // itself can still use the entire width and touch both viewport edges.
    static const int LABEL_SAMPLE[5] = { 0, 32, 64, 96, 127 };
    [loop] for (int xl = 0; xl < 5; ++xl)
    {
        int value = LABEL_SAMPLE[xl];
        float x = sampleX((float)value / 127.0, R.x);
        int digits = value < 10 ? 1 : value < 100 ? 2 : 3;
        float labelW = (float)digits * SUI3_ADVANCE * s;
        float labelX = clamp(x - labelW * 0.5, 2.0 * s, R.x - labelW - 2.0 * s);
        col += T.dim * 0.92 * sampleLabel(P, float2(labelX, R.y - 12.0 * s), s, value);
    }

    // One segment per covered pixel column, evaluated in pixel space for the
    // same stable antialiasing at every output aspect. Positive phase in the
    // producer samples f(x + phase), so the shape travels visibly to the left.
    float u = R.x > 1.0 ? saturate((P.x - 0.5) / (R.x - 1.0)) : 0.0;
    float recordPos = u * 127.0;
    uint i0 = min((uint)floor(recordPos), 126u);
    uint i1 = i0 + 1u;
    float2 a = float2(sampleX(Samples[i0].sample_u, R.x),
                      signalY(Samples[i0].value, R.y));
    float2 b = float2(sampleX(Samples[i1].sample_u, R.x),
                      signalY(Samples[i1].value, R.y));
    float curve = sui3Line(P, a, b, max(1.65, 1.65 * s));
    col = lerp(col, TRACE_RED, curve);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
