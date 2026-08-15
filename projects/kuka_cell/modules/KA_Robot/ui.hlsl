// KA_Robot / ui.hlsl — one thread, once a cook, reducing viewport events into durable state.
//
// This exists only so SPACE can toggle the Scope, and it is a whole pass because a shader cannot
// write a parameter: the toggle has to live somewhere that survives the next cook, which means a
// persistent buffer, which means somebody has to own writing it. Following the events-module
// pattern from knowledge/module-pipeline.md — reduce once here, fan out through the buffer —
// rather than having the full-resolution scope pass rescan the event array per pixel.
//
// TWO INPUTS, LAST ONE WINS. The Scope checkbox in Properties and the Space key are both
// legitimate ways to ask for the same thing, and a build where one silently overrides the other
// is the duplicated-authority trap this project has already been bitten by twice. So the key
// toggles the live state, and the checkbox is adopted only when it actually CHANGES — the
// previous parameter value is remembered here for exactly that comparison. Flip the checkbox and
// it wins; press Space and it wins; neither ever fights the other for a frame.
#include "../_shared/cell.hlsli"

StructuredBuffer<KaBall> Rally : register(t0);
RWStructuredBuffer<KaUi> Ui : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    KaUi u = Ui[0];

    // First cook on a fresh buffer: adopt the parameter rather than starting blank.
    if (u.init < 0.5)
    {
        u.shown = (scope_on > 0.5) ? 1.0 : 0.0;
        u.prevParam = scope_on;
        u.prevTouch = -1.0;     // sentinel: adopt the live count next, do not fire on cook one
        u.timer = 0.0;
        u.init = 1.0;
    }

    // The checkbox moved, so the checkbox is what the user just said.
    if (abs(scope_on - u.prevParam) > 0.001)
    {
        u.shown = (scope_on > 0.5) ? 1.0 : 0.0;
        u.prevParam = scope_on;
    }

    // R, on the press edge only. Key events are type 4, phase 1; A-Z are codes 1-26, so R is 18.
    //
    // It was SPACE first and Space did not arrive. Space is the kind of key a host keeps for
    // itself — transport, play/pause — so a module asking for it is competing with the
    // application rather than being handed an event. A letter has no such claim on it, and R sits
    // under the hand that is already on WASD flying the camera.
    //
    // Reading the PRESS EDGE from the event array rather than through ViewportKeyDown() is what
    // makes this a toggle instead of a strobe: a held key is down for every cook, and this module
    // cooks hundreds of times a second, so a level test would flip the state hundreds of times
    // before the key came back up. That is exactly the mistake the Serve button shipped with.
    uint n = min(_ViewportEventCount, 64u);
    for (uint i = 0u; i < n; i++)
    {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 4u && e.phase == 1u && e.code == 18u &&
            (e.flags & VIEWPORT_EVENT_FLAG_REPEAT) == 0u)
        {
            u.shown = (u.shown > 0.5) ? 0.0 : 1.0;
            u.timer = 0.0;      // a hand on the key restarts the dwell, never truncates it
            u.s1 = 0.0;         // ...and restarts the hit count, so the next cut is a full run
        }
    }

    // AUTO CYCLE — the show mode: alternate the two views on a timer so the thing can be left
    // running on a screen and read without anybody touching it.
    //
    // Timed on _DeltaTime, NOT on a per-cook counter. This module cooks at the GPU's rate rather
    // than the display's — often hundreds of times a second — so counting cooks would make the
    // period depend on how fast the machine happens to be, and the same project would cycle at a
    // completely different speed on another GPU. This is the same rule that governs every rate in
    // the project: integrate against real time, never against frames.
    //
    // Scope Share splits the period asymmetrically, because the two views are not worth equal
    // time. The instrument answers a question and the render is the thing itself; a long look at
    // the machines with a short diagnostic interruption reads far better than a metronome.
    int mode = (int)scope_auto;

    // The rally's cumulative contact count. Monotonic, so any change is a touch that just
    // happened — no thresholds, no windows, and it cannot be missed or double-counted however
    // fast this pass cooks relative to the simulation.
    float touch = Rally[KA_HEADER].power;
    if (u.prevTouch < 0.0) u.prevTouch = touch;      // first cook: adopt, do not fire

    if (mode == 1)          // TIMED
    {
        u.timer += _DeltaTime;
        float period = max(scope_cycle, 0.2);
        float share  = clamp(scope_duty, 0.05, 0.95);
        float dwell  = (u.shown > 0.5) ? period * share : period * (1.0 - share);
        if (u.timer >= dwell)
        {
            u.shown = (u.shown > 0.5) ? 0.0 : 1.0;
            u.timer = 0.0;
        }
    }
    else if (mode == 2)     // ON VOLLEY — the cut lands on the hit
    {
        // Cutting on the contact rather than on a clock is a different thing to watch: the
        // change is CAUSED by the rally instead of merely coinciding with it, so the edit reads
        // as the machines driving the camera. It also paces itself — a long rally cuts fast, a
        // rally that dies leaves the view still while the ball is served again.
        // Hits Per Cut. Every touch on 1, every other touch on 2, and so on — cutting on every
        // single contact is right for a slow rally and far too busy once the ball is moving
        // between neighbours, so the divisor is the thing that makes this usable across both.
        if (touch != u.prevTouch)
        {
            u.s1 += 1.0;
            if (u.s1 >= max(round(scope_hits), 1.0))
            {
                u.shown = (u.shown > 0.5) ? 0.0 : 1.0;
                u.s1 = 0.0;
                u.timer = 0.0;
            }
        }
    }
    else
    {
        u.timer = 0.0;
    }

    u.prevTouch = touch;

    Ui[0] = u;
}
