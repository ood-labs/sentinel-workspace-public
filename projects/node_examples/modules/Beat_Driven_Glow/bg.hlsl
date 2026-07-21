// c1_bg: static mauve-gray studio gradient for the metallic polyhedron reference.
RWTexture2D<float4> OutputUAV : register(u0);

float h11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float radial = saturate(length(p - float2(-0.05, -0.08)) * 1.25);
    float vertical = uv.y;
    float3 top = float3(0.62, 0.58, 0.64);
    float3 mid = float3(0.40, 0.34, 0.40);
    float3 bottom = float3(0.12, 0.085, 0.105);

    float3 col = lerp(top, mid, smoothstep(0.02, 0.56, vertical));
    col = lerp(col, bottom, smoothstep(0.45, 1.0, vertical));
    col += (1.0 - radial) * 0.055 * highlight;
    col *= 1.0 - vignette * dot(p, p) * 0.50;

    float grain = (h11(dot((float2)px, float2(1.0, 113.0))) - 0.5) * grain_amount;
    col += grain;

    OutputUAV[px] = float4(saturate(col), 1.0);
}
