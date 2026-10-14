// KA_Rally / history.hlsl — a short memory of how long the rallies run, for the PLAY pane.
//
// The rally pass books every finished rally into two monotonic counters (completed rallies, and the
// touches booked with them — the same pair published as the `rallies` and `touches` control
// outputs). Each time `rallies` moves on, the touches booked since the last move are that rally's
// length, and it is pushed into a ring of the last 24. Reads the rally header only; the rally pass
// never reads this buffer and nothing downstream depends on it.
#include "../_shared/cell.hlsli"
StructuredBuffer<KaBall> Rally : register(t0);
RWStructuredBuffer<float4> Hist : register(u0);
#define HIST_N 24u
#define HIST_MAGIC 260941.0

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    KaBall hdr = Rally[KA_HEADER];
    float rallies = hdr.a4, touches = hdr.a5;
    float4 head = Hist[0];                      // (rallies seen, touches seen, rallies recorded, magic)

    // first cook, or the counters went back (a fresh rally buffer): start clean
    if (head.w != HIST_MAGIC || rallies < head.x || touches < head.y || rallies - head.x > 4096.0)
    {
        [loop] for (uint k = 1u; k <= HIST_N; k++) Hist[k] = float4(0.0, 0.0, 0.0, 0.0);
        Hist[0] = float4(rallies, touches, 0.0, HIST_MAGIC);
        return;
    }
    if (rallies > head.x)
    {
        // Catch-up safe: the counters are monotonic, so however many rallies were booked since the
        // last cook, each gets its share of the touches booked with them (one rally per booking in
        // practice, so this is that rally's exact length).
        float k = rallies - head.x;
        float len = (touches - head.y) / k;
        uint n = (uint)min(k, (float)HIST_N);
        uint w = (uint)head.z;
        [loop] for (uint j = 0u; j < n; j++)
        {
            Hist[1u + (w % HIST_N)] = float4(len, rallies - (float)(n - 1u - j), 1.0, 0.0);
            w++;
        }
        Hist[0] = float4(rallies, touches, (float)w, HIST_MAGIC);
    }
}
