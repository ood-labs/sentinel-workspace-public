struct AzimuthControl
{
    float direction_x;
    float direction_y;
    float confidence;
    float measured_radius;
};

RWStructuredBuffer<AzimuthControl> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 orientationState = _Tex0.SampleLevel(LinearSampler, float2(0.5, 0.5), 0);
    AzimuthControl control;
    control.direction_x = orientationState.r * 2.0 - 1.0;
    control.direction_y = orientationState.g * 2.0 - 1.0;
    control.confidence = orientationState.b;
    control.measured_radius = measure_radius;
    OutputBuffer[0] = control;
}
