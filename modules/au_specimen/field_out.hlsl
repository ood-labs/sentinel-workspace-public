// AUTOPSIA — raw specimen field published for downstream analysis and relief.
// r = density, g/b = gradient (x8, biased), a = operator heat.
RWTexture2D<float4> FieldTex : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float4 f = _Tex0.SampleLevel(LinearSampler, uv, 0);
    FieldTex[tid.xy] = float4(saturate(f.r),
                              saturate(f.g * 8.0 + 0.5),
                              saturate(f.b * 8.0 + 0.5),
                              saturate(f.a));
}
