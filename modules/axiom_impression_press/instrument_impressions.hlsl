RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float previewEdge(Texture2D tex, float2 uv, float2 px)
{
    float x0 = luminance(tex.SampleLevel(LinearSampler, uv - float2(px.x, 0.0), 0).rgb);
    float x1 = luminance(tex.SampleLevel(LinearSampler, uv + float2(px.x, 0.0), 0).rgb);
    float y0 = luminance(tex.SampleLevel(LinearSampler, uv - float2(0.0, px.y), 0).rgb);
    float y1 = luminance(tex.SampleLevel(LinearSampler, uv + float2(0.0, px.y), 0).rgb);
    return saturate(length(float2(x1 - x0, y1 - y0)) * 2.35);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float topology = max(previewEdge(_Tex0, uv, px * 2.0),
                         luminance(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb) * 0.32);

    float sideDistance = min(uv.x, 1.0 - uv.x);
    float sideGate = 1.0 - smoothstep(preview_inset * 0.42, preview_inset, sideDistance);
    float2 pressureUv = float2(frac(uv.x / max(preview_inset, 0.01)), uv.y);
    if (uv.x > 0.5) pressureUv.x = 1.0 - pressureUv.x;
    float pressure = previewEdge(_Tex1, pressureUv, px * 2.5) * sideGate;

    float borderDistance = min(uv.y, 1.0 - uv.y);
    float rhythmGate = 1.0 - smoothstep(preview_inset * 0.35, preview_inset, borderDistance);
    float bandIndex = floor(uv.y * 12.0);
    float2 rhythmUv = float2(uv.x, frac(uv.y * 3.0 + bandIndex * 0.137));
    float rhythm = previewEdge(_Tex2, rhythmUv, px * 2.0) * rhythmGate;

    float plateWindow = smoothstep(0.03, 0.16, sideDistance)
                      * smoothstep(0.03, 0.16, borderDistance);
    topology *= lerp(0.42, 1.0, plateWindow);

    OutputUAV[tid.xy] = float4(saturate(topology),
                               saturate(pressure),
                               saturate(rhythm),
                               saturate(max(sideGate, rhythmGate)));
}
