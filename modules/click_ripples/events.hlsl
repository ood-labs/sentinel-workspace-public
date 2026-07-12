// THE event-consumer pass: a single-thread (dispatch [1,1,1]) reduction of
// _ViewportEvents into the persistent state buffer. Small explicit-dispatch
// passes receive the event array reliably; full-resolution passes must not
// read _ViewportEvents (they act on this buffer instead).
//
// State buffer layout (row 0):
//   (0,0) ctrl  = (palette index, brush radius, queue generation, init marker)
//   (1..8, 0)   = splat queue: (x, y, strength, generation); strength < 0 = clear
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    float4 ctrl = _Tex0.Load(int3(0, 0, 0));
    if (ctrl.a < 0.5) ctrl = float4(0.0, 0.10, 0.0, 1.0); // first-run defaults

    // Wheel resizes the brush (frame-summed scroll notches).
    ctrl.g = clamp(ctrl.g * (1.0 + _ViewportWheelDelta * 0.12), 0.02, 0.35);

    float4 queue[8];
    uint queued = 0;
    bool clearNow = false;

    uint count = min(_ViewportEventCount, 64u);
    for (uint i = 0; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        // Key presses: type 4, phase 1. Codes: A-Z = 1-26, so C=3, X=24.
        if (e.type == 4u && e.phase == 1u && e.code == 3u)  ctrl.r = fmod(ctrl.r + 1.0, 4.0);
        if (e.type == 4u && e.phase == 1u && e.code == 24u) clearNow = true;
        // Paint sources: raw left press (type 2, phase 1, code 0), click gesture
        // (type 5, code 1), and drag gesture begin/update/end (type 5, code 3,
        // phases 5/6/7; 8 = cancel).
        bool press = (e.type == 2u && e.phase == 1u && e.code == 0u);
        bool click = (e.type == 5u && e.code == 1u);
        bool drag  = (e.type == 5u && e.code == 3u && e.phase != 8u);
        if ((press || click || drag) && queued < 8u) {
            queue[queued] = float4(e.position, drag ? 0.55 : 1.0, 0.0);
            queued += 1u;
        }
    }

    if (clearNow || queued > 0u) ctrl.b += 1.0;           // bump queue generation
    if (ctrl.b > 100000.0) ctrl.b = 1.0;                  // stay in FP32-exact range

    OutputUAV[uint2(0, 0)] = ctrl;
    for (uint s = 0; s < 8u; ++s) {
        float4 entry = float4(0.0, 0.0, 0.0, ctrl.b);
        if (clearNow && s == 0u) entry = float4(0.0, 0.0, -1.0, ctrl.b);
        else if (s < queued) entry = float4(queue[s].xy, queue[s].z, ctrl.b);
        OutputUAV[uint2(1u + s, 0)] = entry;
    }
}
