// Phage_Show / history - a short memory of every lane's triggers for the monitor's tape: each time a
// lane's trigger count moves on, the beat it moved on (and, for BUILD, the ramp) is pushed into that
// lane's ring. Reads the Show State only; nothing downstream depends on this buffer.
#include "../_shared/phage_show.hlsli"
StructuredBuffer<float4> S : register(t0);
RWStructuredBuffer<float4> Hist : register(u0);
#define HIST_N 64u
#define HIST_MAGIC 260936.0

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (S[2].w != 260934) return;
    float beat = S[2].y;
    [unroll] for (uint lane = 0u; lane < 5u; lane++)
    {
        uint h = lane * (HIST_N + 1u);
        float4 head = Hist[h];                       // (last trigger count, write index, magic, -)
        float4 l = S[3 + lane];
        // first cook, or the count went back (lane source switched, build re-armed): start clean
        if (head.z != HIST_MAGIC || l.z < head.x || l.z - head.x > 4096.0)
        {
            [loop] for (uint k = 1u; k <= HIST_N; k++) Hist[h + k] = float4(-1e9, 0, 0, 0);
            Hist[h] = float4(l.z, 0, HIST_MAGIC, 0);
            continue;
        }
        if (l.z > head.x)
        {
            uint w = (uint)head.y % HIST_N;
            Hist[h + 1u + w] = float4(beat, lane == 3u ? l.y : 1.0, 0, 0);
            Hist[h] = float4(l.z, (float)((w + 1u) % HIST_N), HIST_MAGIC, 0);
        }
    }
}
