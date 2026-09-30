// BLINK_Previs / finish.hlsl: the StageRig renderer's present.hlsl (StageRig) as a compute pass.
// HDR scene + multiscale bloom + horizontal streaks, then a camera-style highlight shoulder: low
// exposure keeps chroma, hot saturated cores roll toward neutral white, then 1-exp(-c) and gamma.
RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h; OutputUAV.GetDimensions(w, h); if (id.x >= w || id.y >= h) return;
    float2 uv = (id.xy + .5) / float2(w, h);
    float3 sharp = _Tex0.SampleLevel(PointSampler, uv, 0).rgb;
    float3 soft = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 streak = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 c = (lerp(sharp, soft, saturate(bloom)) + streak * streak_strength) * exposure;
    float peak = max(c.r, max(c.g, c.b));
    float white = 1 - exp(-max(0, peak - sensor_white_start) * sensor_response);
    c = lerp(c, peak.xxx, white);
    c = 1 - exp(-c);
    OutputUAV[id.xy] = float4(pow(max(c, 0), 1 / 2.2), 1);
}
