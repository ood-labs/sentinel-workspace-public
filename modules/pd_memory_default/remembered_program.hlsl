RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> ProgramInput : register(t0);
Texture2D<float4> MemoryInput : register(t1);
Texture2D<float4> CurrentEmission : register(t2);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 resolution = float2((float)width, (float)height);
    float2 uv = ((float2)tid.xy + 0.5) / resolution;
    float2 texel = 1.0 / resolution;
    float3 program = ProgramInput.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 memory = MemoryInput.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 current = CurrentEmission.SampleLevel(LinearSampler, uv, 0).rgb;

    float memoryLuma = dot(memory, float3(0.299, 0.587, 0.114));
    float memoryRight = dot(MemoryInput.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb, float3(0.299, 0.587, 0.114));
    float memoryUp = dot(MemoryInput.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb, float3(0.299, 0.587, 0.114));
    float memoryEdge = length(float2(memoryRight - memoryLuma, memoryUp - memoryLuma));

    float3 base = program * current_gain;
    float3 remembered = memory * memory_gain;
    float3 screenBlend = base + remembered * (1.0 - base);
    float currentLuma = dot(current, float3(0.299, 0.587, 0.114));
    float liveCut = smoothstep(0.28, 0.75, currentLuma) * (0.08 + default_impulse * 0.26);
    screenBlend = lerp(screenBlend, current, liveCut);
    screenBlend += liability_color * memoryEdge * etch_gain;

    float2 p = uv - (vanishing_point * 0.5 + 0.5);
    float depthVignette = saturate(1.0 - dot(p, p) * 0.38);
    screenBlend *= lerp(0.86, 1.0, depthVignette);

    float border =
        step(0.009, uv.x) * step(uv.x, 0.991) *
        step(0.016, uv.y) * step(uv.y, 0.984);
    screenBlend *= border;

    OutputUAV[tid.xy] = float4(saturate(screenBlend), 1.0);
}
