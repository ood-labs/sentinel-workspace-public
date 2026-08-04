// TP_Render / pick.hlsl — turn a drag on the BEAUTY image into a position on the water.
//
// This is what makes the headline interaction work. The mouse is over a perspective render of a
// tank, and the simulation needs a footprint coordinate; the camera is the only thing that can
// connect the two, and the camera lives here. So the pick is cast from the same injected
// _InvViewProjMatrix the render uses, against the STILL water plane at y = 0.
//
// Against the still plane rather than the displaced surface on purpose: the displaced surface
// moves under the cursor while you are pushing it, so picking against it would make the contact
// point chase its own wake and the stroke would smear. The still plane is where the user thinks
// they are pointing.
//
// The result leaves as control outputs and returns to TP_Sim through expressions rather than a
// data link, so there is no cycle in the graph — only a one-frame delay, which for water is
// nothing.
#include "../_shared/tessera.hlsli"

StructuredBuffer<TpRec> Plan : register(t1);
RWStructuredBuffer<float4> PickOut : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    TpRec tank = Plan[TP_TANK];
    float3 half3 = tpTankHalf(tank);

    float4 st = PickOut[0];
    // .w holds the DRAG state, .z holds what was published last cook. They must be separate:
    // seeding `down` from the published value re-latches a one-shot click on the next cook and
    // the finger is pressed forever again, which is the bug this pair exists to prevent.
    // .w is a HOLD TIMER in seconds, not a flag.
    //
    // A boolean here cannot be cleared reliably: the only event that would clear it is a
    // drag-end, and events stop arriving entirely the moment the preview loses focus — so a
    // drag that ends off-focus strands the flag at true and the sim presses a finger into the
    // water forever, immune to every damping control because it is re-imposed every cook. That
    // is exactly the "it never calms down" symptom, and it survives project reloads because the
    // buffer is persistent.
    //
    // A timer cannot strand: it decays to zero on its own unless something keeps renewing it.
    // Range-clamped on read because this slot previously held a cook counter, so an older saved
    // project restores a value in the thousands.
    float hold = clamp(st.w, 0.0, 1.0);
    hold = max(hold - _DeltaTime, 0.0);
    float2 uv = st.xy;

    // Viewport gesture ABI v1 identifies "drag" but does not carry the originating mouse
    // button. With camera + events on the same viewport, that means an RMB camera drag can
    // otherwise look identical to an LMB water drag. Element 1 latches RMB ownership from the
    // raw pointer edge and suppresses the generic gesture until its end/cancel. A left press
    // always recovers ownership if focus/capture was interrupted.
    float4 route = PickOut[1];
    bool routeSane = abs(route.w - 0.731) < 0.001;
    bool rightOwned = routeSane && route.x > 0.5;

    uint n = min((uint)_ViewportEventCount, 64u);
    bool sawMove = false;
    bool clicked = false;
    float2 screen = float2(0.5, 0.5);

    for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];

        // Raw pointer code: left 0, right 1. Process these before HOST_CONSUMED because the
        // camera is expected to consume RMB while the event reducer still needs its ownership.
        if (ev.type == 2u && ev.code == 1u && ev.phase == 1u)
        {
            rightOwned = true;
            hold = 0.0;
        }
        if (ev.type == 2u && ev.code == 0u && ev.phase == 1u)
            rightOwned = false;

        if ((ev.flags & VIEWPORT_EVENT_FLAG_HOST_CONSUMED) != 0u)
        {
            if (ev.type == 5u && rightOwned && (ev.phase == 7u || ev.phase == 8u))
                rightOwned = false;
            continue;
        }

        if (ev.type == 5u)
        {
            // Fallback for hosts that expose the generic drag but not the raw RMB edge.
            if (ev.code == 3u && ev.phase == 5u && (_ViewportButtons & 2u) != 0u)
                rightOwned = true;

            if (rightOwned)
            {
                if (ev.phase == 7u || ev.phase == 8u) rightOwned = false;
                continue;
            }

            if (ev.code == 3u)                                    // drag
            {
                // Renew the hold. A quarter second is long enough to ride out a drag where the
                // pointer is held still and stops emitting updates, and short enough that a
                // released drag stops pushing before the next ripple crosses the tank.
                if (ev.phase == 5u || ev.phase == 6u) { hold = 0.25; sawMove = true; screen = ev.position; }
                else hold = 0.0;                                  // end / cancel
            }
            else if (ev.code == 1u && ev.phase == 7u)             // click
            {
                // A click is an INSTANT, and it has no release event to pair with. Latching
                // `down` here left the pointer pressed forever after a single click anywhere on
                // the water — a permanent finger holding a dent in the surface, immune to every
                // damping control because it is re-imposed every cook. Record the position and
                // let the impulse flag carry the one-shot.
                clicked = true; sawMove = true; screen = ev.position;
            }
        }
    }

    if (sawMove)
    {
        float2 ndc = float2(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0);
        float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
        nearW /= nearW.w;
        farW  /= farW.w;

        float3 ro = _CameraPos;
        float3 rd = normalize(farW.xyz - nearW.xyz);

        if (abs(rd.y) > 1e-4)
        {
            float t = -ro.y / rd.y;
            if (t > 0.0)
            {
                float3 p = ro + rd * t;
                // Outside the tank the pick is simply refused. Clamping instead would pin the
                // stroke to the wall and keep pushing there, which looks like a stuck finger.
                if (abs(p.x) <= half3.x && abs(p.z) <= half3.z)
                    uv = float2(p.x / half3.x * 0.5 + 0.5, p.z / half3.z * 0.5 + 0.5);
                else
                    hold = 0.0;
            }
            else hold = 0.0;
        }
    }

    // A click contributes one cook of contact and then lets go; only a live drag holds, and
    // only for as long as it keeps renewing the timer.
    PickOut[0] = float4(uv, ((hold > 0.0) || clicked) ? 1.0 : 0.0, hold);
    PickOut[1] = float4(rightOwned ? 1.0 : 0.0, 0.0, 0.0, 0.731);
}
