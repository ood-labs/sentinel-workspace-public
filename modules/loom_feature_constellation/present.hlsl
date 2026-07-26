RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float3 col = _Tex0.Load(int3(id.xy, 0)).rgb * exposure;
    float vignette = smoothstep(1.05, 0.18, length((uv - 0.5) * float2(_Resolution.x/_Resolution.y, 1.0)));
    col *= 0.62 + 0.62 * vignette;
    col = saturate(col);
    OutputUAV[id.xy] = float4(col, 1.0);
}
