// il_events.hlsli - Interaction Lab kit: ordered viewport events, consumed exactly once.
//
// Include only from a Module whose manifest declares `viewport.interactions: [events]`
// (that is what injects _ViewportEvents / _ViewportEventCount).
//
// THE FOUR INPUT RULES (every one was a shipped bug somewhere first):
//  1. Consume each event once, by `sequence`. The host hands the same event back on later cooks
//     until newer input replaces it: unguarded, one wheel notch scales forever and a held key
//     strobes. Keep the last consumed sequence in a persistent buffer (bit-exact via asuint).
//  2. The host counter restarts at zero on app restart/project load while the persisted
//     watermark does not. If the ring is non-empty and its newest sequence is BELOW the
//     watermark, the counter reset: drop the watermark to zero (ilEvWatermark does this).
//  3. Scale wheel actions by the notch amount (ev.value, fractional on precision wheels),
//     clamped per event - never "one step per event".
//  4. Latch toggles: flip on a non-repeat press while unlatched, re-arm on release.
//
// Reduce events ONCE in a dispatch [1,1,1] pass that owns the state buffer; full-resolution
// passes read derived state only.
#ifndef IL_EVENTS_HLSLI
#define IL_EVENTS_HLSLI

// type
#define IL_EV_MOVE     1u
#define IL_EV_BUTTON   2u
#define IL_EV_WHEEL    3u
#define IL_EV_KEY      4u
#define IL_EV_GESTURE  5u
#define IL_EV_CAPTURE  6u
// phase
#define IL_PH_PRESS    1u
#define IL_PH_REPEAT   2u
#define IL_PH_RELEASE  3u
#define IL_PH_DOUBLE   4u
#define IL_PH_BEGIN    5u
#define IL_PH_UPDATE   6u
#define IL_PH_END      7u
#define IL_PH_CANCEL   8u
// pointer button code
#define IL_BTN_LEFT    0u
#define IL_BTN_RIGHT   1u
#define IL_BTN_MIDDLE  2u
// gesture code
#define IL_GE_CLICK    1u
#define IL_GE_DOUBLE   2u
#define IL_GE_DRAG     3u
// key code
// letters are 1..26 (HLSL has no char literals, so they are spelled out)
#define IL_KEY_A 1u
#define IL_KEY_B 2u
#define IL_KEY_C 3u
#define IL_KEY_D 4u
#define IL_KEY_E 5u
#define IL_KEY_F 6u
#define IL_KEY_G 7u
#define IL_KEY_H 8u
#define IL_KEY_I 9u
#define IL_KEY_J 10u
#define IL_KEY_K 11u
#define IL_KEY_L 12u
#define IL_KEY_M 13u
#define IL_KEY_N 14u
#define IL_KEY_O 15u
#define IL_KEY_P 16u
#define IL_KEY_Q 17u
#define IL_KEY_R 18u
#define IL_KEY_S 19u
#define IL_KEY_T 20u
#define IL_KEY_U 21u
#define IL_KEY_V 22u
#define IL_KEY_W 23u
#define IL_KEY_X 24u
#define IL_KEY_Y 25u
#define IL_KEY_Z 26u
#define IL_KEY_0 32u                              // digits 0..9 are 32..41
#define IL_KEY_ESC 48u
#define IL_KEY_TAB 49u
#define IL_KEY_ENTER 50u
#define IL_KEY_SPACE 51u
#define IL_KEY_BACKSPACE 52u
#define IL_KEY_LEFT 53u
#define IL_KEY_RIGHT 54u
#define IL_KEY_UP 55u
#define IL_KEY_DOWN 56u
#define IL_KEY_SHIFT 57u
#define IL_KEY_CTRL 58u
#define IL_KEY_ALT 59u

uint ilEvCount() { return min(_ViewportEventCount, 64u); }

bool ilEvFresh(uint seq, uint lastSeq) { return seq > lastSeq || (lastSeq - seq) > (1u << 20); }

// Rule 2: returns the watermark to use this cook (0 after a host counter reset).
uint ilEvWatermark(uint lastSeq)
{
    uint n = ilEvCount();
    uint ringMax = 0u;
    [loop] for (uint i = 0u; i < n; i++) ringMax = max(ringMax, _ViewportEvents[i].sequence);
    return (n > 0u && ringMax < lastSeq) ? 0u : lastSeq;
}

// Advance a running "newest consumed" value past ev.
uint ilEvAdvance(uint newest, uint lastSeq, uint seq) { return (seq > lastSeq) ? max(newest, seq) : seq; }

bool ilShift(ViewportEvent e) { return (e.modifiers & VIEWPORT_MODIFIER_SHIFT) != 0u; }
bool ilCtrl(ViewportEvent e)  { return (e.modifiers & VIEWPORT_MODIFIER_CONTROL) != 0u; }
bool ilAlt(ViewportEvent e)   { return (e.modifiers & VIEWPORT_MODIFIER_ALT) != 0u; }
bool ilRepeat(ViewportEvent e) { return (e.flags & VIEWPORT_EVENT_FLAG_REPEAT) != 0u || e.phase == IL_PH_REPEAT; }

bool ilIsPress(ViewportEvent e, uint btn)   { return e.type == IL_EV_BUTTON && e.phase == IL_PH_PRESS && e.code == btn; }
bool ilIsRelease(ViewportEvent e, uint btn) { return e.type == IL_EV_BUTTON && e.phase == IL_PH_RELEASE && e.code == btn; }
bool ilIsClick(ViewportEvent e)  { return e.type == IL_EV_GESTURE && e.code == IL_GE_CLICK && e.phase == IL_PH_END; }
bool ilIsDouble(ViewportEvent e) { return e.type == IL_EV_GESTURE && e.code == IL_GE_DOUBLE; }
bool ilIsDrag(ViewportEvent e)   { return e.type == IL_EV_GESTURE && e.code == IL_GE_DRAG; }
// The host ended a gesture for us: Escape during pointer capture is consumed by the router (it
// cancels the capture and never arrives as a key), as do disable, reload and preview close.
bool ilIsCancel(ViewportEvent e)
{
    return e.phase == IL_PH_CANCEL && (e.type == IL_EV_GESTURE || e.type == IL_EV_CAPTURE || e.type == IL_EV_BUTTON)
        || (e.flags & VIEWPORT_EVENT_FLAG_CAPTURE_CANCEL) != 0u;
}
bool ilIsKeyDown(ViewportEvent e, uint code) { return e.type == IL_EV_KEY && e.phase == IL_PH_PRESS && e.code == code; }
bool ilIsKeyUp(ViewportEvent e, uint code)   { return e.type == IL_EV_KEY && e.phase == IL_PH_RELEASE && e.code == code; }

// Rule 3: notches for one wheel event, clamped to +-3.
float ilWheel(ViewportEvent e)
{
    float v = (abs(e.value) > 1e-4) ? e.value : e.delta.y;
    return clamp(v, -3.0, 3.0);
}

// Rule 4: a latched toggle. `held` is a persisted bit for this key. Returns true on the one cook
// where the toggle should flip.
bool ilLatch(ViewportEvent e, uint code, inout bool held)
{
    if (e.type != IL_EV_KEY || e.code != code) return false;
    if (e.phase == IL_PH_PRESS && !ilRepeat(e) && !held) { held = true; return true; }
    if (e.phase == IL_PH_RELEASE) held = false;
    return false;
}

// Event position in output pixels.
float2 ilEvPx(ViewportEvent e, float2 res) { return e.position * res; }

#endif
