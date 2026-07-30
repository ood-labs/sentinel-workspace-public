// TouchDesigner-style vertical image displacement.
//
// Input 0 is the meaningful jellybeans image. Input 1 is the floating-point
// 128x64 signal texture. Its red channel is read across X and converted around
// Midpoint into a vertical UV offset.

RWTexture2D<float4> OutputUAV : register(u0);

float mirrorCoordinate(float x)
{
    return 1.0 - abs(frac(x * 0.5) * 2.0 - 1.0);
}

float4 sampleExtended(float2 uv)
{
    int mode = (int)round(extend_mode);
    if (mode == 1)
    {
        bool outside = any(uv < 0.0) || any(uv > 1.0);
        return outside ? float4(0.0, 0.0, 0.0, 0.0)
                       : _Tex0.SampleLevel(LinearSampler, uv, 0);
    }
    if (mode == 2)
        return _Tex0.SampleLevel(LinearSampler, frac(uv), 0);
    if (mode == 3)
        return _Tex0.SampleLevel(LinearSampler,
                                 float2(mirrorCoordinate(uv.x),
                                        mirrorCoordinate(uv.y)), 0);
    return _Tex0.SampleLevel(LinearSampler, saturate(uv), 0);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = (float2(tid.xy) + 0.5) / _Resolution.xy;
    float2 signalUv = offset + (uv - offset) * uv_weight;
    float signal = _Tex1.SampleLevel(LinearSampler,
                                     float2(signalUv.x, signalUv.y), 0).r;

    float vertical = (signal - midpoint) * vertical_weight
                   + (offset.y - 0.5) * offset_weight;
    float2 displacedUv = uv - float2(0.0, vertical);
    OutputUAV[tid.xy] = sampleExtended(displacedUv);
}
