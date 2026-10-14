// Plotter / ink - the sheet: one ink density per pen in a persistent RGBA16F texture, read and
// written in this one pass. Old ink fades with the ink memory's half-life; this cook's marks are
// added on top.
//
// Each mark is a half-open slab of the line: a pixel takes ink from the mark whose span contains
// its nearest point (0 <= t < 1), so consecutive marks - in one cook or across two - never lay ink
// twice at their joint, and a stroke drawn in short steps does not bead. Only a stroke's real ends
// (and sharp turns) get round caps; that overlap is where a pen pools ink anyway.
#include "plotter.hlsli"

StructuredBuffer<float4> PL : register(t0);       // the plan: marks and bounds
RWTexture2D<float4> OutputUAV : register(u0);     // the sheet (slot 1 reads it as _Tex1)

[numthreads(16, 16, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 p = (float2)id.xy + 0.5;
    float4 d = _Tex1.Load(int3(id.xy, 0));
    if (badValue(d) || any(d < 0.0)) d = 0.0;
    // the half-life: the top of the range keeps everything
    float hl = clamp(memory, 2.0, 600.0);
    if (hl < 599.0) d *= exp2(-clamp(_DeltaTime, 0.0, 0.1) / hl);

    uint n = (uint)PL[PL_NMARKS].x;
    float4 bb = PL[PL_BOUNDS];
    if (n > 0u && all(p >= bb.xy) && all(p <= bb.zw))
    {
        [loop] for (uint i = 0u; i < n; i++)
        {
            float4 ab = PL[PL_MARK0 + 2u * i], q = PL[PL_MARK0 + 2u * i + 1u];
            float2 a = ab.xy, ba = ab.zw - ab.xy;
            float l2 = dot(ba, ba);
            uint caps = (uint)q.w;
            float t = l2 > 1e-8 ? dot(p - a, ba) / l2 : 0.0;
            if (l2 <= 1e-8) caps = CAP_START | CAP_END;
            if (t < 0.0 && (caps & CAP_START) == 0u) continue;
            if (t >= 1.0 && (caps & CAP_END) == 0u) continue;
            float dist = length(p - (a + ba * saturate(t)));
            float cov = smoothstep(q.z + 0.75, q.z - 0.75, dist);
            uint pen = (uint)q.y;
            d += cov * q.x * float4(pen == 0u, pen == 1u, pen == 2u, pen == 3u);
        }
    }
    OutputUAV[id.xy] = min(d, 64.0);
}
