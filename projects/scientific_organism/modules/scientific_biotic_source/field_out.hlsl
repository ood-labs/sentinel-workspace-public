RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float4 field = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float density = saturate(field.r);
    float edge = saturate(length(field.gb * 2.0 - 1.0) * 3.0);
    OutputUAV[tid.xy] = float4(density.xxx + edge * 0.18, 1.0);
}
