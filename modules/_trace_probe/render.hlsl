// Exercises the span and drawing half of the header.

#include "../_shared/ui/sui3_trace.hlsli"

StructuredBuffer<float4>  Ring      : register(t0);
RWTexture2D<float4>       OutputUAV : register(u0);

static const uint TP_CAP  = 512u;
static const uint TP_HEAD = 512u;

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float2 R = _Resolution.xy;
    if (tid.x >= (uint)R.x || tid.y >= (uint)R.y) return;

    float2 P = float2(tid.xy) + 0.5;
    float3 col = float3(0.006, 0.006, 0.007);

    float4 r = float4(20.0, 20.0, R.x - 20.0, R.y - 20.0);

    float4 st = Ring[TP_HEAD];
    float writeIdx = st.y;
    float peak     = st.z;

    float fs    = sui3FullScale(peak, 0.3, 0.05, 1.15);
    float nShow = sui3TraceSamples(4.0, 1.0 / 187.5, TP_CAP);

    int i0, i1;
    sui3TraceSpan(P.x, r.x, r.z, nShow, writeIdx, i0, i1);

    float v = 0.0;
    [loop] for (int i = i0; i <= i1; ++i) {
        if (i < 0) continue;
        v = max(v, Ring[sui3TraceAt(0u, TP_CAP, (uint)i)].x);
    }

    float norm = saturate(v / max(fs, 1e-6));

    col += 0.30 * sui3StripFill(P, r, norm);
    col += 0.60 * sui3StripRef(P, r, saturate(0.3 / max(fs, 1e-6)), 6.0);
    col += 0.20 * sui3StripTick(P, r, 0.0);
    col += 0.50 * sui3StripBase(P, r);

    // Round-trip the axis mapping so both directions are compile-checked.
    float back = sui3StripValue(r, sui3StripY(r, norm));
    col += 0.0 * back;

    OutputUAV[tid.xy] = float4(col, 1.0);
}
