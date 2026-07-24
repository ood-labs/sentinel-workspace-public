RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    // Sentinel compacts declared video inputs into runtime texture registers:
    // Atmosphere=Tex0, Grid=Tex1, Accent=Tex2, HUD=Tex3, Wire=Tex4.
    col += _Tex1.SampleLevel(LinearSampler, uv, 0).rgb * grid_gain;
    col += _Tex2.SampleLevel(LinearSampler, uv, 0).rgb * accent_gain;
    col += _Tex3.SampleLevel(LinearSampler, uv, 0).rgb * hud_gain;
    float3 wire = _Tex4.SampleLevel(LinearSampler, uv, 0).rgb;
    col += wire * wire_tint * wire_gain;
    OutputUAV[pixel] = float4(col * master_mix, 1.0);
}
