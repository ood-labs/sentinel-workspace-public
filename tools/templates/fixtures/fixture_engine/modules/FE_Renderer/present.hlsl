// The camera, ported from PHAGE's present: the HDR image blended toward its bloom, plus anamorphic streaks,
// exposure, then the sensor: above sensor_white_start the max channel bleeds into the others at
// sensor_response, so low exposure keeps chroma and hot saturated cores roll toward a neutral clip.
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    float2 uv = ((float2)id.xy + 0.5) / float2(w, h);
    float3 sharp = _Tex0.SampleLevel(PointSampler, uv, 0).rgb;
    float3 soft = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 streak = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 c = (lerp(sharp, soft, saturate(bloom)) + streak * streak_strength) * exposure;
    float peak = max(c.r, max(c.g, c.b));
    float white = 1.0 - exp(-max(0.0, peak - sensor_white_start) * sensor_response);
    c = lerp(c, peak.xxx, white);
    c = 1.0 - exp(-c);
    OutputUAV[id.xy] = float4(pow(max(c, 0.0), 1.0 / 2.2), 1.0);
}
