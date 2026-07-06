// signal display — 4 horizontal meter bars so the LFO node is readable in the graph.

struct SigData { float pulse; float sweep; float beat; float slow; };
StructuredBuffer<SigData> Sig : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    SigData s = Sig[0];
    float vals[4] = { s.pulse, s.sweep, s.beat, s.slow };
    int row = (int)(uv.y * 4.0);
    float v = vals[clamp(row, 0, 3)];
    float bar = step(uv.x, v);
    float3 col = lerp(float3(0.1, 0.2, 0.3), float3(1.0, 0.6, 0.2), (float)row / 3.0) * bar;
    OutputUAV[pixel] = float4(col, 1.0);
}
