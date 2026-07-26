RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float3 a = _Tex0.Load(int3(id.xy,0)).rgb;
    float3 b = _Tex1.Load(int3(id.xy,0)).rgb;
    float3 col = a + max(b - bloom_threshold, 0.0) * bloom_gain;
    float y = dot(col, float3(0.2126,0.7152,0.0722));
    col = lerp(y.xxx, col, saturation);
    col = (col - 0.5) * contrast + 0.5;
    if (posterize > 0.001) {
        float steps = lerp(48.0, poster_steps, posterize);
        col = floor(col * steps + 0.5) / steps;
    }
    float scan = 0.5 + 0.5 * sin(uv.y * _Resolution.y * 3.14159265);
    col *= 1.0 - scanlines * scan * 0.12;
    float vignette = smoothstep(1.05, 0.22, length((uv - 0.5) * float2(_Resolution.x/_Resolution.y,1.0)));
    col *= 1.0 - vignette_strength + vignette_strength * vignette;
    col = saturate(col * exposure);
    OutputUAV[id.xy] = float4(col, 1.0);
}
