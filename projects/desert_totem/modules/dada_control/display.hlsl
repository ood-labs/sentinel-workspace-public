// dada_control preview — four labelled bars showing the live macro values.
struct Ctrl { float melt; float sag; float spread; float explode; float p4; float p5; float p6; float p7; };
StructuredBuffer<Ctrl> In : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    Ctrl c = In[0];
    float vals[4] = { saturate(c.melt), saturate(c.sag), saturate((c.spread - 0.3) / 1.9), saturate(c.explode / 3.0) };
    float3 cols[4] = { float3(0.90, 0.45, 0.20), float3(0.55, 0.35, 0.80), float3(0.25, 0.65, 0.55), float3(0.85, 0.70, 0.20) };

    int bar = (int)(uv.x * 4.0);
    bar = clamp(bar, 0, 3);
    float within = frac(uv.x * 4.0);
    float v = vals[bar];

    float3 col = float3(0.10, 0.10, 0.13);
    if (within > 0.12 && within < 0.88)
        col = (1.0 - uv.y) < v ? cols[bar] : float3(0.16, 0.16, 0.19);
    OutputUAV[px] = float4(col, 1.0);
}
