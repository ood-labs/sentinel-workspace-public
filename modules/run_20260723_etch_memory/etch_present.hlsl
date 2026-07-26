RWTexture2D<float4> OutputUAV : register(u0);

float ep_box_line(float2 p, float2 center, float2 halfSize, float width)
{
    float2 d = abs(p - center) - halfSize;
    float signedDistance = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    return 1.0 - smoothstep(width, width * 2.0, abs(signedDistance));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float4 memory = _Tex0.Load(int3(pixel, 0));
    float px = 1.0 / max(_Resolution.y, 1.0);
    float luma = dot(memory.rgb, float3(0.2126, 0.7152, 0.0722));

    float quantized = floor(saturate(luma) * (float)tone_steps + 0.5) / max((float)tone_steps, 1.0);
    float3 monochrome = paper_tint * quantized;
    float hot = saturate(memory.r - max(memory.g, memory.b) * 1.05);
    float3 col = lerp(memory.rgb, monochrome, monochrome_pull);
    col = lerp(col, accent_color, hot * accent_recovery);

    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float phaseMark = (scan_phase - 0.5) * 0.72;
    float marker = ep_box_line(p, float2(phaseMark, 0.445), float2(0.032, 0.012), px);
    marker += ep_box_line(p, float2(phaseMark, -0.445), float2(0.032, 0.012), px);
    col = max(col, marker.xxx * paper_tint * phase_marker);

    float borderDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float border = 1.0 - smoothstep(px * 1.5, px * 3.5, borderDistance);
    col = max(col, border.xxx * paper_tint * border_weight);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
