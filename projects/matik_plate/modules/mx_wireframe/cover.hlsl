// mx_wireframe / cover.hlsl — publishes the wire layer's coverage as a separate lane.
//
// The molecules are opaque: they must hide the micro-marks behind them. Colour alone cannot
// carry that, because a sphere's interior is black and so is the background. Coverage is a
// different contract from colour, so it gets its own output rather than being smuggled into
// the colour lane's alpha (which would also make this module's own preview read wrong).

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    float a = saturate(_Tex0.SampleLevel(LinearSampler, uv, 0).a);
    OutputUAV[px] = float4(a, a, a, 1.0);
}
