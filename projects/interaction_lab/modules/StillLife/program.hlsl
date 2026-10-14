// Still Life / program - the clean output: one blit of the solve.
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    OutputUAV[id.xy] = float4(_Tex0.Load(int3(id.xy, 0)).rgb, 1.0);
}
