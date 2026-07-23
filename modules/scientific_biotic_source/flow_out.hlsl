RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float4 field = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float2 gradient = field.gb * 2.0 - 1.0;
    float2 flow = normalize(float2(-gradient.y, gradient.x) + 1e-5) * saturate(length(gradient) * 5.0);
    OutputUAV[tid.xy] = float4(flow * 0.5 + 0.5, saturate(length(gradient) * 4.0), 1.0);
}
