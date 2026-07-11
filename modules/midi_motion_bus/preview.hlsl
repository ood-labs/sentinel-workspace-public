struct MotionBus {
    float phase;
    float beat;
    float pad_energy;
    float knob_energy;
    float sweep;
    float palette;
    float loop_seconds;
    float reserved;
};

StructuredBuffer<MotionBus> In : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    MotionBus b = In[0];

    float3 bg = float3(0.018, 0.022, 0.035);
    float3 cyan = float3(0.02, 0.85, 1.0);
    float3 magenta = float3(1.0, 0.08, 0.56);
    float grid = step(0.97, frac(uv.x * 16.0)) + step(0.95, frac(uv.y * 4.0));
    float playhead = 1.0 - smoothstep(0.0, 0.012, abs(uv.x - b.phase));
    float beatCell = floor(uv.x * 4.0);
    float beatOn = 1.0 - step(0.001, abs(beatCell - floor(b.phase * 4.0)));
    float lower = step(0.55, uv.y) * beatOn * step(0.14, frac(uv.x * 4.0)) * step(frac(uv.x * 4.0), 0.86);
    float3 col = bg + grid * 0.018;
    col += cyan * playhead * 1.4;
    col += lerp(cyan, magenta, uv.x) * lower * 0.45;
    OutputUAV[px] = float4(col, 1.0);
}
