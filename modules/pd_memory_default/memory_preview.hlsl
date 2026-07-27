RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> MemoryInput : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 uv = ((float2)tid.xy + 0.5) / float2((float)width, (float)height);
    float4 memory = MemoryInput.SampleLevel(LinearSampler, uv, 0);
    float grid = 1.0 - smoothstep(0.02, 0.06, min(abs(frac(uv.x * 24.0) - 0.5), abs(frac(uv.y * 14.0) - 0.5)));
    float3 color = memory.rgb + float3(0.12, 0.13, 0.12) * grid * 0.04;
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
