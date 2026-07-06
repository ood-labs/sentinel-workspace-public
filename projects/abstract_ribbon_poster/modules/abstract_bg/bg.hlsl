// abstract_bg: soft studio-poster background, floor contact shadows, and faint paper grain.

RWTexture2D<float4> OutputUAV : register(u0);

float hash21_local(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(asp, 1.0);

    float3 topCol = float3(0.86, 0.86, 0.84);
    float3 midCol = float3(0.76, 0.76, 0.73);
    float3 floorCol = float3(0.91, 0.90, 0.87);
    float3 col = lerp(topCol, midCol, smoothstep(0.0, 0.75, uv.y));

    float floorBlend = smoothstep(0.78, 0.96, uv.y);
    col = lerp(col, floorCol, floorBlend);

    float horizon = 1.0 - smoothstep(0.0, 0.006, abs(uv.y - 0.865));
    col -= horizon * 0.035;

    float ell1 = exp(-((p.x + 0.04) * (p.x + 0.04) / 0.035 + (uv.y - 0.875) * (uv.y - 0.875) / 0.0012));
    float ell2 = exp(-((p.x - 0.18) * (p.x - 0.18) / 0.028 + (uv.y - 0.885) * (uv.y - 0.885) / 0.0007));
    float ell3 = exp(-((p.x + 0.18) * (p.x + 0.18) / 0.018 + (uv.y - 0.845) * (uv.y - 0.845) / 0.0010));
    col -= float3(0.09, 0.085, 0.075) * shadow_strength * saturate(ell1 + 0.45 * ell2 + 0.35 * ell3);

    float vignette = dot(p, p) * 0.22 + smoothstep(0.12, 0.72, abs(uv.y - 0.48)) * 0.035;
    col -= vignette;

    float grain = hash21_local((float2)pixel + floor(_Time * 18.0)) - 0.5;
    col += grain * grain_amount;

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
