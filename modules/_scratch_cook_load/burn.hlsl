// Deliberate GPU load. See manifest.yaml - test fixture only.

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    float acc = 0.0;
    float2 z = uv * 3.0 - 1.5;
    uint n = (uint)clamp(iterations, 1.0, 60000.0);
    [loop] for (uint i = 0u; i < n; ++i) {
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + (uv - 0.5);
        acc += sin(z.x * 1.7 + _Time) * cos(z.y * 1.3);
        z = clamp(z, -2.0, 2.0);
    }
    float v = saturate(abs(acc) / max((float)n, 1.0));
    OutputUAV[px] = float4(v, v, v, 1.0);
}
