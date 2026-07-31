// mx_wireframe / flatten.hlsl — resolves the draw pass onto an opaque black plate.
//
// The rasterized pass leaves untouched pixels at alpha 0, so the module's own preview would
// read as "white background" in any viewer that composites over white. The plate is black;
// make that explicit here rather than leaving every downstream consumer to guess.

// _Tex0 and LinearSampler are engine-injected for a pass input; declaring them is a redefinition.
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    float4 src = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float3 col = src.rgb * src.a;   // premultiplied over black
    OutputUAV[px] = float4(col, 1.0);
}
