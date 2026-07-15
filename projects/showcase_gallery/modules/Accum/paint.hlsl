// accum paint — composites the incoming stamp layer (_Tex0 = Face_Cutout) over the (already
// transformed) canvas snapshot (CanvasPrev) and writes the persistent canvas. decay=1 keeps
// imprints forever; <1 = fading trails. clear!=0 zeroes the canvas. One thread per pixel.

RWStructuredBuffer<float4> Canvas     : register(u0);   // output: buffer:canvas (persistent)
StructuredBuffer<float4>   CanvasPrev : register(t1);   // input: buffer:canvas_prev (t0 = _Tex0)

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    uint W = (uint)_Resolution.x, H = (uint)_Resolution.y;
    if (px.x >= W || px.y >= H) return;
    uint idx = px.y * W + px.x;

    if (clear != 0) { Canvas[idx] = float4(0, 0, 0, 0); return; }

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float4 nw = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float4 prev = CanvasPrev[idx];

    prev *= decay;
    float a = saturate(nw.a * paint);
    float3 col = prev.rgb * (1.0 - a) + nw.rgb * a;
    float oa = saturate(max(prev.a, a));
    Canvas[idx] = float4(col, oa);
}
