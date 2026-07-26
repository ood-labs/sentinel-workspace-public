RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    // (0,0): brush radius, queue generation, erase mode, initialized
    float4 ctrl = _Tex0.Load(int3(0, 0, 0));
    if (ctrl.a < 0.5) ctrl = float4(0.10, 0.0, 0.0, 1.0);
    ctrl.r = clamp(ctrl.r * (1.0 + _ViewportWheelDelta * 0.12), 0.018, 0.34);

    float4 queue[8];
    uint queued = 0u;
    bool clearNow = false;

    uint count = min(_ViewportEventCount, 64u);
    for (uint i = 0u; i < count; ++i)
    {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 4u && e.phase == 1u && e.code == 5u) ctrl.b = 1.0 - ctrl.b; // E
        if (e.type == 4u && e.phase == 1u && e.code == 24u) clearNow = true;       // X

        bool press = e.type == 2u && e.phase == 1u && e.code == 0u;
        bool click = e.type == 5u && e.code == 1u;
        bool drag = e.type == 5u && e.code == 3u && e.phase != 8u;
        if ((press || click || drag) && queued < 8u)
        {
            float strength = ctrl.b > 0.5 ? -1.0 : (drag ? 0.55 : 1.0);
            queue[queued] = float4(e.position, strength, 0.0);
            queued += 1u;
        }
    }

    if (clearNow || queued > 0u) ctrl.g += 1.0;
    if (ctrl.g > 100000.0) ctrl.g = 1.0;
    OutputUAV[uint2(0, 0)] = ctrl;

    for (uint s = 0u; s < 8u; ++s)
    {
        float4 entry = float4(0.0, 0.0, 0.0, ctrl.g);
        if (clearNow && s == 0u) entry = float4(0.0, 0.0, -8.0, ctrl.g);
        else if (s < queued) entry = float4(queue[s].xy, queue[s].z, ctrl.g);
        OutputUAV[uint2(1u + s, 0)] = entry;
    }
}
