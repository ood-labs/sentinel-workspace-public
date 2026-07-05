// label_gen preview — small ticks at each label anchor (text is drawn by label_render).

struct LabelRecord
{
    float2 pos; float scale; float label_id;
    float color_mix; float rotation; float active; float pad0;
};

StructuredBuffer<LabelRecord> Labels : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float m = 0.0;
    [loop]
    for (uint i = 0u; i < 48u; i++)
    {
        LabelRecord L = Labels[i];
        if (L.active < 0.5) continue;
        float2 d = (uv - L.pos) * float2(asp, 1.0);
        m = max(m, 1.0 - smoothstep(0.0, 0.006, length(d)));
    }
    OutputUAV[pixel] = float4(float3(0.9, 0.8, 0.5) * m, m);
}
