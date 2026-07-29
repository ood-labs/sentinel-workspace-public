RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    col = saturate((col - 0.5) * press_contrast + 0.5);
    OutputUAV[tid.xy] = float4(col, 1.0);
}

