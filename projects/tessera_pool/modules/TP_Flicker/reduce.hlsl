// TP_Flicker / reduce.hlsl — the numbers.
//
// `flicker_area` is the one that settles arguments: the FRACTION OF THE IMAGE that changed by
// more than a visible threshold this frame. A mean can be dragged down to a comfortable-looking
// value by a large calm region while a quarter of the frame strobes; an area fraction cannot.
StructuredBuffer<float4> Hist : register(t0);
RWStructuredBuffer<float4> Metrics : register(u0);

groupshared float gMean[256];
groupshared float gPeak[256];
groupshared float gArea[256];

[numthreads(256, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint gi : SV_GroupIndex)
{
    uint n = (uint)(src_width * src_height);

    float mn = 0.0, pk = 0.0, ar = 0.0;
    for (uint i = gi; i < n; i += 256u)
    {
        float4 h = Hist[i];
        float hold = (abs(h.y) < 1e5) ? h.y : 0.0;
        float inst = (abs(h.z) < 1e5) ? h.z : 0.0;
        mn += inst;
        pk = max(pk, hold);
        ar += (inst > max(area_threshold, 1e-5)) ? 1.0 : 0.0;
    }
    gMean[gi] = mn; gPeak[gi] = pk; gArea[gi] = ar;
    GroupMemoryBarrierWithGroupSync();

    for (uint s = 128u; s > 0u; s >>= 1)
    {
        if (gi < s)
        {
            gMean[gi] += gMean[gi + s];
            gPeak[gi]  = max(gPeak[gi], gPeak[gi + s]);
            gArea[gi] += gArea[gi + s];
        }
        GroupMemoryBarrierWithGroupSync();
    }

    if (gi == 0u)
    {
        float fn = max((float)n, 1.0);
        // All four in element 0: a control output bound to element 1 of a buffer reads back as
        // exactly zero in this build while element 0 reads correctly.
        Metrics[0] = float4(gMean[0] / fn, gPeak[0], gArea[0] / fn, fn);
    }
}
