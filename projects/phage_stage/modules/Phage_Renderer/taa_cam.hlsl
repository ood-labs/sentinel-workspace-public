// Temporal anti-aliasing: keep this frame's (unjittered) view-projection and camera position for next frame's
// reprojection. Declared after taa.hlsl, so taa reads the previous frame's.
RWStructuredBuffer<float4> Out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    Out[0] = _ViewProjMatrix[0];
    Out[1] = _ViewProjMatrix[1];
    Out[2] = _ViewProjMatrix[2];
    Out[3] = _ViewProjMatrix[3];
    Out[4] = float4(_CameraPos, 1.0);
}
