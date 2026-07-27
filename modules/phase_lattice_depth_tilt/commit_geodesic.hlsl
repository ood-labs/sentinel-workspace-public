struct GeodesicPoint
{
    float2 position;
    float progress;
    float confidence;
};

StructuredBuffer<GeodesicPoint> Current : register(t0);
RWStructuredBuffer<GeodesicPoint> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    [unroll]
    for (uint i = 0; i < 24; ++i)
        OutputBuffer[i] = Current[i];
}
