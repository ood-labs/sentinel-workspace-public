// Preview meter for abstract_signal.

struct SigData { float pulse; float sweep; float beat; float slow; };
StructuredBuffer<SigData> Sig : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float getValue(int i, SigData s)
{
    if (i == 0) return s.pulse;
    if (i == 1) return s.sweep;
    if (i == 2) return s.beat;
    return s.slow;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    SigData s = Sig[0];
    int row = clamp((int)(uv.y * 4.0), 0, 3);
    float v = getValue(row, s);
    float bar = step(uv.x, v);
    float stripe = 1.0 - smoothstep(0.0, 0.018, abs(frac(uv.x * 10.0) - 0.5));
    float3 base = lerp(float3(0.08, 0.10, 0.12), float3(0.95, 0.42, 0.14), (float)row / 3.0);
    float3 col = base * (bar * (0.72 + stripe * 0.28));
    OutputUAV[pixel] = float4(col, 1.0);
}
