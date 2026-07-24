RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float3 current = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 history = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float currentLuma = dot(current, float3(0.2126, 0.7152, 0.0722));
    float historyLuma = dot(history, float3(0.2126, 0.7152, 0.0722));
    float difference = abs(currentLuma - historyLuma);

    float3 col = history;
    if (memory_mode == 1) col = lerp(current, history, saturate(memory * 0.84));
    if (memory_mode == 2)
    {
        float residue = smoothstep(trail_threshold * 0.45, trail_threshold + 0.12, difference);
        col = lerp(current, history, residue * trail_gain);
    }

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col = lerp(col, paper_color, smoothstep(0.0028, 0.0010, border) * 0.30);
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
