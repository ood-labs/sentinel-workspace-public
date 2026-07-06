// abstract_column: right-side triangle column clipped to a tall rectangle.

RWTexture2D<float4> OutputUAV : register(u0);

float hash11_local(float n)
{
    return frac(sin(n) * 43758.5453);
}

float rectMask(float2 uv, float2 mn, float2 mx, float feather)
{
    float2 a = smoothstep(mn, mn + feather, uv);
    float2 b = 1.0 - smoothstep(mx - feather, mx, uv);
    return a.x * a.y * b.x * b.y;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 mn = float2(0.635 + x_offset, 0.075);
    float2 mx = float2(0.835 + x_offset, 0.910);
    float mask = rectMask(uv, mn, mx, 0.002);

    float2 loc = saturate((uv - mn) / max(mx - mn, 0.001));
    float cols = 4.0;
    float rows = 13.0;
    float2 g = loc * float2(cols, rows);
    float2 cell = floor(g);
    float2 f = frac(g);
    float triId = step(f.x, f.y);
    float id = cell.x + cell.y * 17.0 + triId * 53.0;

    float val = hash11_local(id + 7.0);
    float shade = lerp(0.14, 0.88, val);
    shade = lerp(shade, 0.58, 0.25 * sin(cell.y * 1.7 + triId));

    float edgeA = 1.0 - smoothstep(0.0, 0.020, min(abs(f.x - f.y), min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y))));
    float3 col = float3(shade, shade, shade) + edgeA * 0.045;

    float glass = smoothstep(0.0, 0.05, loc.x) * (1.0 - smoothstep(0.95, 1.0, loc.x));
    col = lerp(col, float3(0.86, 0.86, 0.84), glass * 0.12);
    col *= 1.0 - loc.y * 0.06;

    float sideLine = (1.0 - smoothstep(0.0, 0.0018, abs(uv.x - mx.x))) * smoothstep(mn.y, mn.y + 0.01, uv.y) * (1.0 - smoothstep(mx.y - 0.01, mx.y, uv.y));
    col += sideLine * 0.15;

    OutputUAV[pixel] = float4(col * mask * opacity, mask * opacity);
}
