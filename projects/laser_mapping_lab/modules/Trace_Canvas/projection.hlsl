// Projection: the 16:9 frame for the video projector.
#include "canvas.hlsli"
RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h; OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    // Pixel centre in frame units, and this pass's own pixel size in frame units per axis.
    float2 px = float2(FW / w, 1.0 / h);
    float2 p = (id.xy + 0.5) * px;
    OutputUAV[id.xy] = float4(artColour(p, px), 1);
}
