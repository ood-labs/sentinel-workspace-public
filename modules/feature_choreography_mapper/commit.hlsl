struct GlyphRecord
{
    float2 position;
    float2 direction;
    float weight;
    float kind;
    float group_id;
    float active;
};

StructuredBuffer<GlyphRecord> Current : register(t0);
RWStructuredBuffer<GlyphRecord> PreviousOut : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x < 64u)
    {
        PreviousOut[id.x] = Current[id.x];
    }
}
