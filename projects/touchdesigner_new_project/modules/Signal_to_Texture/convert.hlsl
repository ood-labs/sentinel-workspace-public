// Converts the 128 scalar Hermite records into a 128x64 floating-point image.
// Every row carries the same signal, matching TouchDesigner's CHOP-to-TOP
// adaptation: the X coordinate is the sample index and red is the displacement
// value consumed downstream.

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float u = _Resolution.x > 1.0
        ? (float)tid.x / (_Resolution.x - 1.0)
        : 0.0;
    uint sampleIndex = min((uint)round(u * 127.0), 127u);
    float value = _Data0[sampleIndex].value;
    if (clamp_values != 0) value = saturate(value);

    OutputUAV[tid.xy] = float4(value, value, value, 1.0);
}
