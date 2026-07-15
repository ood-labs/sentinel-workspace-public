// hud_comp — FUI compositor. bg is the opaque base; every other layer is additive.
// Inputs: 0 BG, 1 Orbits, 2 Gauge, 3 Labels, 4 Splines, 5..11 chain Layers (each
// a self-contained pl_render output). Chain layers share one gain so the whole
// cloner set balances together.

RWTexture2D<float4> OutputUAV : register(u0);

float3 tap(Texture2D t, float2 uv){ return t.SampleLevel(LinearSampler, uv, 0).rgb; }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float3 col = tap(_Tex0, uv) * bg_gain;
    col += tap(_Tex1, uv) * orbits_gain;
    col += tap(_Tex2, uv) * gauge_gain;
    col += tap(_Tex3, uv) * labels_gain;
    col += tap(_Tex4, uv) * splines_gain;

    float3 layers = tap(_Tex5, uv) + tap(_Tex6, uv) + tap(_Tex7, uv)
                  + tap(_Tex8, uv) + tap(_Tex9, uv) + tap(_Tex10, uv) + tap(_Tex11, uv);
    col += layers * layers_gain;

    col *= master_mix;
    OutputUAV[pixel] = float4(col, 1.0);
}
