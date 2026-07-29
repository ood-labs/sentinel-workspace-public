RWTexture2D<float4> OutputUAV : register(u0);

float lineMask(float x, float width)
{
    return 1.0 - smoothstep(width, width + 0.75 / _Resolution.y, abs(x));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    uint srcW, srcH;
    _Tex0.GetDimensions(srcW, srcH);
    float srcAspect = (float)srcW / max(1.0, (float)srcH);
    float dstAspect = _Resolution.x / _Resolution.y;
    float2 suv = uv;
    if (srcAspect > dstAspect)
        suv.x = (uv.x - 0.5) * dstAspect / srcAspect + 0.5;
    else
        suv.y = (uv.y - 0.5) * srcAspect / dstAspect + 0.5;
    suv = (suv - 0.5) / max(0.35, crop_scale) + 0.5 + crop_offset;

    float3 src = _Tex0.SampleLevel(LinearSampler, saturate(suv), 0).rgb;
    float luma = dot(src, float3(0.299, 0.587, 0.114));
    src = lerp(luma.xxx, src, chroma);
    src = saturate((src - 0.5) * contrast + 0.5);
    float steps = max(2.0, poster_steps);
    src = floor(src * steps + 0.5) / steps;

    float paperNoise = hash21(px * 0.73) - 0.5;
    float3 paper = paper_color + paperNoise * paper_grain;
    float ink = smoothstep(0.72, 0.18, luma);
    float3 col = lerp(paper, src, image_mix);
    col = lerp(col, ink_color, ink * ink_mix);

    float2 cell = frac(uv * float2(16.0, 9.0));
    float grid = max(lineMask(cell.x - 0.5, grid_width),
                     lineMask(cell.y - 0.5, grid_width));
    col = lerp(col, ink_color, grid * grid_opacity);

    float2 q = uv * float2(_Resolution.x / _Resolution.y, 1.0);
    float diag = lineMask(frac((q.x + q.y) * 7.0) - 0.5, 0.018);
    col = lerp(col, accent_color, diag * accent_routes);

    float border = 1.0 - step(0.012, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
    col = lerp(col, ink_color, border);
    OutputUAV[px] = float4(saturate(col), 1.0);
}
