RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> ParticleField : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;
    float2 uv = ((float2)tid.xy + 0.5) / float2((float)width, (float)height);
    float4 field = ParticleField.SampleLevel(LinearSampler, uv, 0);
    OutputUAV[tid.xy] = float4(field.rgb, 1.0);
}
