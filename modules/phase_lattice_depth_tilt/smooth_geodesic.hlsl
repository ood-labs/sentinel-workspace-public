struct GeodesicPoint
{
    float2 position;
    float progress;
    float confidence;
};

StructuredBuffer<GeodesicPoint> Target : register(t0);
StructuredBuffer<GeodesicPoint> Previous : register(t1);
RWStructuredBuffer<GeodesicPoint> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float retention = pow(
        saturate(path_memory),
        max(_DeltaTime * 60.0, 0.25));

    [unroll]
    for (uint i = 0; i < 24; ++i)
    {
        GeodesicPoint targetPoint = Target[i];
        GeodesicPoint previousPoint = Previous[i];
        float initialized = step(0.001, previousPoint.confidence);

        GeodesicPoint resolved;
        resolved.position = lerp(
            targetPoint.position,
            previousPoint.position,
            retention * initialized);
        resolved.progress = targetPoint.progress;
        resolved.confidence = lerp(
            targetPoint.confidence,
            previousPoint.confidence,
            retention * initialized);
        OutputBuffer[i] = resolved;
    }
}
