// botany_comp — Botany Bouquet compositor. Opaque violet bg, then the drifting crop-frame, then
// the bouquet render (both premultiplied), stacked Over. Inlet order: 0 bg, 1 frame, 2 render.
RWTexture2D<float4> OutputUAV : register(u0);

float3 over(float3 dst, float4 src, float gain){
    float3 pr = src.rgb * gain; float a = saturate(src.a * gain);
    return pr + dst*(1.0 - a);
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;      // opaque bg
    col = over(col, _Tex1.SampleLevel(LinearSampler, uv, 0), frame_gain);
    col = over(col, _Tex2.SampleLevel(LinearSampler, uv, 0), render_gain);
    OutputUAV[px] = float4(saturate(col), 1.0);
}
