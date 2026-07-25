struct P { uint slot, cook, magic, extra; };
StructuredBuffer<P> Probe : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    uint band = min(px.y * 8u / (uint)_Resolution.y, 7u);
    P p = Probe[band];
    float v = (p.cook > 0u) ? 0.85 : 0.12;
    OutputUAV[px] = float4(v, v, v, 1.0);
}
