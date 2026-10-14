// Generation_Controller / history - the activity ring the canvas draws: one sample every 1/32 s
// whatever the cook rate (up to 8 a cook, so a slow frame catches up instead of stretching time),
// each recording whether a render window was open (hold 0) at any cook since the last sample, and
// how many stamps fired. Reads generation_state, which update.hlsl alone writes; writes only this
// ring, which nothing but the layout reads.
#include "gc_history.hlsli"

StructuredBuffer<float4> State : register(t0);
RWStructuredBuffer<float4> Hist : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float stampCycle = State[3].x;
    float open = State[0].x < 0.5 ? 1.0 : 0.0;
    float4 h0 = Hist[0];
    if (Hist[1].x != GH_MAGIC)
    {
        [loop] for (uint i = 0u; i < GH_N; i++) Hist[GH_FIRST + i] = float4(0.0, 0.0, 0.0, 0.0);
        h0 = float4(0.0, 0.0, stampCycle, 0.0);
        Hist[1] = float4(GH_MAGIC, 0.0, 0.0, 0.0);
    }

    float seen = max(h0.w, open);                     // a window that opened and shut between samples still shows
    float stamps = max(stampCycle - h0.z, 0.0);       // a reset counter reads as none, never negative
    uint head = (uint)h0.x % GH_N;
    float clock = h0.y + max(_DeltaTime, 0.0);
    uint written = 0u;
    [loop] for (uint k = 0u; k < 8u && clock >= GH_DT; k++)
    {
        clock -= GH_DT;
        Hist[GH_FIRST + head] = float4(k == 0u ? seen : open, k == 0u ? stamps : 0.0, 0.0, 0.0);
        head = (head + 1u) % GH_N;
        written++;
    }
    bool sampled = written > 0u;
    Hist[0] = float4((float)head, min(clock, GH_DT), sampled ? stampCycle : h0.z, sampled ? 0.0 : seen);
}
