// mx_composite / comp.hlsl — stacks the plate.
//
// Bottom to top: circuitry (the micro-mark field), then the organisms, then the instrument
// panels. That order is what the reference shows — hairlines and marks run under the
// molecules, and panels sit opaquely over both.
//
// Panel coverage is DERIVED HERE from the Plate records rather than shipped as a texture
// from MX_Instruments, so the rectangle that knocks out is provably the same rectangle the
// instrument was drawn into. The organisms need a real coverage lane instead, because a
// sphere's interior is black and indistinguishable from the background by colour alone.
#include "../_shared/plate.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 circuitry, _Tex1 wire colour, _Tex2 wire coverage, _Tex3 instruments,
// LinearSampler and _Data0 (Plate) are engine-injected.

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pix = DTid.xy;
    if (pix.x >= (uint)_Resolution.x || pix.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pix + 0.5) / _Resolution.xy;
    float px = 1.0 / _Resolution.x;

    float3 circ = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 wire = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float  wcov = _Tex2.SampleLevel(LinearSampler, uv, 0).r;
    float3 inst = _Tex3.SampleLevel(LinearSampler, uv, 0).rgb;

    float3 col = circ * circuit_gain;

    col = lerp(col, wire * wire_gain, saturate(wcov * wire_opacity));

    float pcov = 0.0;
    for (uint i = 0u; i < PLATE_CELLS; i++)
    {
        PlateRec r = _Data0[i];
        if (r.role > 0.5 || r.active < 0.5) continue;
        if (r.size.x <= 0.0 || r.size.y <= 0.0) continue;
        float2 q = uv - r.pos;
        float2 e = r.size + panel_pad;
        if (abs(q.x) > e.x + px * 2.0 || abs(q.y) > e.y + px * 2.0) continue;
        pcov = max(pcov, pFill(pBox(q, e), px));
        if (pcov > 0.999) break;
    }

    col = lerp(col, inst * panel_gain, saturate(pcov * panel_opacity));

    OutputUAV[pix] = float4(saturate(col), 1.0);
}
