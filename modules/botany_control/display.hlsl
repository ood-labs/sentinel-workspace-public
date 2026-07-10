// botany_control preview — labelled bars of the live macro values.
struct Ctrl { float seed; float warp; float twist; float spread; float hue_speed; float frame_drift; float bloom; float p7; };
StructuredBuffer<Ctrl> In : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    Ctrl c = In[0];
    float vals[7] = { saturate(c.seed/50.0), saturate(c.warp), saturate(c.twist),
                      saturate((c.spread-0.4)/1.6), saturate(c.hue_speed), saturate(c.frame_drift), saturate(c.bloom) };
    float3 cols[7] = { float3(0.55,0.55,0.58), float3(0.90,0.45,0.20), float3(0.55,0.35,0.80),
                       float3(0.72,0.85,0.07), float3(0.90,0.20,0.55), float3(0.25,0.65,0.85), float3(0.95,0.80,0.20) };

    int bar = clamp((int)(uv.x*7.0), 0, 6);
    float within = frac(uv.x*7.0);
    float3 col = float3(0.08,0.07,0.11);
    if (within > 0.12 && within < 0.88){
        float v = vals[bar];
        if (1.0-uv.y < v) col = cols[bar];
        else col = float3(0.16,0.15,0.20);
    }
    OutputUAV[px] = float4(col, 1.0);
}
