// Curve Desk / sample - what the desk publishes: every channel sampled across the loop, and the
// values at the playhead (the control outputs other nodes follow with ref()).
//
// Curves buffer, float4 records:
//   0        (playhead s, phase 0..1, loop length s, playing 0 | 1)
//   1        at the playhead: (travel, height, squash, frame)
//   2..257   sample k at t = k / 255 * length: (travel, height, squash, t)
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "curve.hlsli"

RWStructuredBuffer<float4> C : register(u0);

float3 valuesAt(uint packed, float t)
{
    return float3(cvValue(0u, cvCount(packed, 0u), t), cvValue(1u, cvCount(packed, 1u), t), cvValue(2u, cvCount(packed, 2u), t));
}

[numthreads(CV_SAMPLES, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    CvRec h0 = S[CV_V0], h1 = S[CV_V1];
    uint packed = S[CV_P0].e;
    float len = clamp(length_s, 0.5, 8.0);
    float t = len * (float)gi / (float)(CV_SAMPLES - 1u);
    C[2u + gi] = float4(valuesAt(packed, t), t);
    if (gi == 0u)
    {
        float p = h0.c;
        C[0] = float4(p, p / len, len, (h1.e & CV_PLAYING) != 0u ? 1.0 : 0.0);
        C[1] = float4(valuesAt(packed, p), floor(p * clamp((float)fps, 6.0, 60.0) + 1e-4));
    }
}
