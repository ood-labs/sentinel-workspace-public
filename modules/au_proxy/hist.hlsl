// AUTOPSIA — observation histogram, computed as ONE deterministic reduction.
// A single 64-thread group tallies into groupshared memory (one bin per thread),
// then publishes. No clear pass, no cross-pass ordering hazard, no device atomics.
// Bins 0..63 = luma distribution, [64] = peak of the specimen bins, [65] = total.
RWStructuredBuffer<uint4> Hist : register(u0);

groupshared uint gBins[64];

[numthreads(64, 1, 1)]
void main(uint3 gtid : SV_GroupThreadID) {
    uint lane = gtid.x;
    gBins[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();

    uint w = (uint)_Resolution.x;
    uint h = (uint)_Resolution.y;
    // each lane sweeps an interleaved set of rows, sampling every 2nd column
    [loop] for (uint y = lane; y < h; y += 64u) {
        [loop] for (uint x = 0u; x < w; x += 2u) {
            float v = saturate(_Tex0.Load(int3(int(x), int(y), 0)).r);
            uint b = min((uint)(v * 63.999), 63u);
            InterlockedAdd(gBins[b], 1u);
        }
    }
    GroupMemoryBarrierWithGroupSync();

    uint mine = gBins[lane];
    Hist[lane] = uint4(mine, 0u, 0u, 0u);

    if (lane == 0u) {
        uint peak = 1u;
        uint total = 0u;
        [loop] for (uint i = 0u; i < 64u; ++i) {
            total += gBins[i];
            if (i >= 3u) peak = max(peak, gBins[i]);   // ignore the empty plate
        }
        Hist[64] = uint4(peak, 0u, 0u, 0u);
        Hist[65] = uint4(total, 0u, 0u, 0u);
    }
}
