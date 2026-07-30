// Freeze the live subject or matte when reveal stage 1 begins. Subsequent
// black/white/color stages read the same snapshot, so an evolving StreamDiff
// input cannot change silhouette underneath the reveal.
RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<float4> CanvasState : register(t2);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float action = CanvasState[0].y;
    bool captureNow = action > 0.5 && action < 1.5;
    float4 color = captureNow
        ? _Tex0.SampleLevel(LinearSampler, uv, 0)
        : _Tex1.SampleLevel(LinearSampler, uv, 0);
    OutputUAV[pixel] = color;
}
