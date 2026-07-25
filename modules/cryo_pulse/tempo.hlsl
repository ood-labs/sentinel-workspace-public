// CRYOGRAM / PULSE — parallel tempo autocorrelation.
//
// One thread PER LAG. The previous version ran this whole search inside the
// single-threaded analyze pass: ~100 lags x ~190 taps = 16k iterations and 32k
// structured-buffer loads on ONE GPU lane, with no latency hiding. That does
// not show up in the CPU-side profiler at all, it just quietly throttled the
// module's cook rate to roughly a quarter of the graph's.
//
// Reads last cook's committed history. One-cook latency on a tempo estimate is
// irrelevant; correctness of the onset train is not affected.

struct PS { float a, b, c, d, e, f, g, h; };

StructuredBuffer<PS> Hist : register(t0);
RWStructuredBuffer<float4> AC : register(u0);

static const uint HIST  = 512u;
static const uint HDR_A = 650u;
static const uint MAXLAG = 256u;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint lag = tid.x;
    if (lag >= MAXLAG) return;

    PS A = Hist[HDR_A];
    uint head = (uint)max(A.b, 0.0);

    float score = 0.0;
    if (lag >= 8u && head > 400u) {
        uint win = 384u;
        float s = 0.0, n = 0.0;
        [loop] for (uint k = 0u; k + lag < win; k += 2u) {
            uint i0 = (head - 1u - k) % HIST;
            uint i1 = (head - 1u - k - lag) % HIST;
            s += Hist[i0].d * Hist[i1].d;      // kick-lane onset strength
            n += 1.0;
        }
        score = s / max(n, 1.0);
    }

    AC[lag] = float4(score, (float)lag, 0.0, 0.0);
}
