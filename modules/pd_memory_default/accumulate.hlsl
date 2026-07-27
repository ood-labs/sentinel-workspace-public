RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> CurrentEmission : register(t1);

float2 pdRotate(float2 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 resolution = float2((float)width, (float)height);
    float2 uv = ((float2)tid.xy + 0.5) / resolution;
    float2 vanish = vanishing_point * 0.5 + 0.5;
    float dt = clamp(max(_DeltaTime, 0.004), 0.004, 0.05);

    float2 relative = uv - vanish;
    relative = pdRotate(relative, twist * dt * 0.12);
    float2 previousUv = vanish + relative * (1.0 + advection * dt * 0.12);
    float4 previous = _Tex0.SampleLevel(LinearSampler, previousUv, 0);
    float4 current = CurrentEmission.SampleLevel(LinearSampler, uv, 0);

    float decay = pow(saturate(retention), dt * 60.0);
    float currentLuma = dot(current.rgb, float3(0.299, 0.587, 0.114));
    float currentGate = smoothstep(0.025, 0.22, currentLuma);
    float impulse = saturate(default_impulse);
    float3 depositColor = current.rgb * currentGate * deposit * (0.30 + impulse * 0.95);

    float3 memoryColor = previous.rgb * decay;
    memoryColor = max(memoryColor, depositColor);
    memoryColor += depositColor * dt * (1.2 + impulse * 4.0);

    float memoryAlpha = max(previous.a * decay, currentGate * (0.35 + impulse * 0.65));
    if (clear_memory != 0)
    {
        memoryColor = 0.0;
        memoryAlpha = 0.0;
    }

    OutputUAV[tid.xy] = float4(saturate(memoryColor), saturate(memoryAlpha));
}
