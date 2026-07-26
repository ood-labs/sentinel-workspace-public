// AUTOPSIA — clean observation image published to the Features node.
// No overlay, no annotation: exactly what the instrument's eye receives.
RWTexture2D<float4> Analysis : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float v = _Tex0.Load(int3(tid.xy, 0)).r;
    Analysis[tid.xy] = float4(v, v, v, 1.0);
}
