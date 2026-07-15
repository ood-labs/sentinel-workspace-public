// plate_comp — the strata multi-plate compositor. Stacks premultiplied-alpha plate textures
// bottom->top with per-plate gain + blend mode (Over / Add / Screen), over an opaque base
// (the bg plate). The reusable technique: composite N independently-distorted raymarch/graphic
// plates in 2D screen space — sharp plates frame distorted plates. Inputs are read at this
// node's resolution (plates share 720x1080). Order: 0 bg(opaque base) 1..4 over it.
//
//   slot 0: bg      (opaque)          slot 3: wire    (premult)
//   slot 1: blobs   (premult)         slot 4: marks   (premult)
//   slot 2: marble  (premult)
#include "../_shared/palette.hlsli"

// _Tex0.._Tex4 (from inputs slots 0..4) and LinearSampler are injected by the engine — do
// NOT declare them here (redefinition).
RWTexture2D<float4> OutputUAV : register(u0);

// composite one premultiplied plate (rgb already * a) over the accumulator, with gain + mode.
float3 plate(float3 dst, float4 src, float gain, int mode)
{
    float3 pr = src.rgb * gain;
    float a = saturate(src.a * gain);
    if (mode == 1) return dst + pr;                       // Add
    if (mode == 2) return 1.0 - (1.0 - dst) * (1.0 - saturate(pr)); // Screen
    return pr + dst * (1.0 - a);                          // Over (premultiplied)
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    float4 bg     = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float4 blobs  = _Tex1.SampleLevel(LinearSampler, uv, 0);
    float4 marble = _Tex2.SampleLevel(LinearSampler, uv, 0);
    float4 wire   = _Tex3.SampleLevel(LinearSampler, uv, 0);
    float4 marks  = _Tex4.SampleLevel(LinearSampler, uv, 0);

    float3 col = bg.rgb * bg_gain;                        // opaque base
    col = plate(col, marble, marble_gain, (int)marble_mode);
    col = plate(col, blobs,  blob_gain,   (int)blob_mode);
    col = plate(col, wire,   wire_gain,   (int)wire_mode);
    col = plate(col, marks,  marks_gain,  (int)marks_mode);

    OutputUAV[px] = float4(saturate(col), 1.0);
}
