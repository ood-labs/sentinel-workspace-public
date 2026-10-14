// Temporal anti-aliasing: keep this frame's result as next frame's history (alpha 1 marks it written).
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    OutputUAV[id.xy] = float4(_Tex0[int2(id.xy)].rgb, 1.0);
}
