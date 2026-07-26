RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
    float4 trail = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float lum = dot(trail.rgb, float3(0.299, 0.587, 0.114));
    float neighbor =
        dot(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x * 2.0, 0.0), 0).rgb, float3(0.299, 0.587, 0.114));
    float memoryEdge = smoothstep(0.025, 0.14, abs(lum - neighbor)) * trail.a;

    float3 color = trail.rgb;
    color += memoryEdge * float3(0.075, 0.075, 0.068);

    float scan = 0.985 + 0.015 * sin((float)pixel.y * 3.14159265);
    color *= scan;
    color = saturate(color);

    OutputUAV[pixel] = float4(color, 1.0);
}
