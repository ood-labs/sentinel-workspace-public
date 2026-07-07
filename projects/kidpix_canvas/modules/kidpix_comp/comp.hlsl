// kidpix_comp — the Kid Pix canvas compositor. Opaque WHITE canvas base, then premultiplied-alpha
// paint plates stacked back->front with per-plate gain (all Over, because paint is opaque on the
// canvas). Inlet order matches the reference layering:
//   0 roil  1 trail  2 stroke  3 scribble  4 swarm  5 cube  6 ui
// _Tex0.._Tex6 + LinearSampler injected by the engine. Unconnected inputs sample transparent black
// (a=0) so over() leaves the accumulator untouched.
RWTexture2D<float4> OutputUAV : register(u0);

float3 over(float3 dst, float4 src, float gain)
{
    float3 pr = src.rgb * gain;
    float a = saturate(src.a * gain);
    return pr + dst * (1.0 - a);   // premultiplied Over
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    float3 col = float3(1.0, 1.0, 1.0) * canvas_gain;             // white paper

    col = over(col, _Tex0.SampleLevel(LinearSampler, uv, 0), roil_gain);
    col = over(col, _Tex1.SampleLevel(LinearSampler, uv, 0), trail_gain);
    col = over(col, _Tex2.SampleLevel(LinearSampler, uv, 0), stroke_gain);
    col = over(col, _Tex3.SampleLevel(LinearSampler, uv, 0), scribble_gain);
    col = over(col, _Tex4.SampleLevel(LinearSampler, uv, 0), swarm_gain);
    col = over(col, _Tex5.SampleLevel(LinearSampler, uv, 0), cube_gain);
    col = over(col, _Tex6.SampleLevel(LinearSampler, uv, 0), ui_gain);

    OutputUAV[px] = float4(saturate(col), 1.0);
}
