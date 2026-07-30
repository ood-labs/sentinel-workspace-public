#ifndef SENTINEL_SUI3_EVENTS_HLSLI
#define SENTINEL_SUI3_EVENTS_HLSLI

// Viewport event decoding, v3.
//
// ============================ THE BUTTON TRAP ============================
// `type: button` parameters DO NOT deliver a usable pressed level to HLSL.
// Phase 3A measured the exact behaviour on Sentinel 0.5.49 against
// Motion_Console's `burst`, and it is worse than previously documented
// (AUTOPSIA recorded "reads as a constant 1.0"). The truth is a ONE-WAY LATCH:
//
//   initial              shader reads false
//   after set burst=1    shader reads TRUE
//   after set burst=0    still TRUE  -- the write is ignored
//   after force_reload   still TRUE  -- survives reload, twice
//   after project reload finally false
//
// Because `lfo_compute.hlsl:36` gates a lane on it, one press permanently
// destroyed that lane and the energy readout for the rest of the session.
//
// A second hazard: `sentinel_state get` reported 0.000000 for that parameter
// while `sentinel_pipeline info` reported 1.000000 at the same instant. Trust
// `info` when probing a button.
//
// CONSEQUENCE: never gate shader behaviour on a `type: button` parameter.
// Hit-test a real click gesture instead, which carries an unambiguous position
// and a single completion phase. `type: bool` is unaffected and is safe.
// =========================================================================
//
// Event ABI, confirmed live:
//   click        type 5, code 1, phase 7   (one completed click)
//   drag         type 5, code 3            (phase 8 is the terminator)
//   button press type 2, phase 1, code 0=left 1=right
//   key press    type 4, phase 1, code = virtual key
//
// `e.position` is normalized 0..1 over the panel. Convert to pixels with
// `e.position * _Resolution.xy` before hit-testing anything drawn in pixel
// space -- which, in the v3 language, is everything.

static const uint SUI3_EV_POINTER = 2u;
static const uint SUI3_EV_KEY     = 4u;
static const uint SUI3_EV_GESTURE = 5u;

static const uint SUI3_GESTURE_CLICK = 1u;
static const uint SUI3_GESTURE_DRAG  = 3u;

static const uint SUI3_PHASE_BEGIN    = 1u;
static const uint SUI3_PHASE_COMPLETE = 7u;
static const uint SUI3_PHASE_END      = 8u;

bool sui3IsClick(ViewportEvent e) {
    return e.type == SUI3_EV_GESTURE && e.code == SUI3_GESTURE_CLICK
        && e.phase == SUI3_PHASE_COMPLETE;
}

bool sui3IsDrag(ViewportEvent e) {
    return e.type == SUI3_EV_GESTURE && e.code == SUI3_GESTURE_DRAG
        && e.phase != SUI3_PHASE_END;
}

bool sui3IsPress(ViewportEvent e, uint button) {
    return e.type == SUI3_EV_POINTER && e.phase == SUI3_PHASE_BEGIN && e.code == button;
}

bool sui3IsKey(ViewportEvent e, uint vk) {
    return e.type == SUI3_EV_KEY && e.phase == SUI3_PHASE_BEGIN && e.code == vk;
}

uint sui3EventCount() { return min(_ViewportEventCount, 64u); }

// Returns the index of the button rect containing a completed click, or -1.
// `rects` are in PIXELS. Caller loops the event ring itself when it needs more
// than a bank hit-test.
int sui3HitBank(float2 P_unused, float4 rects[8], int count) {
    int hit = -1;
    uint n = sui3EventCount();
    [loop] for (uint i = 0u; i < n; ++i) {
        ViewportEvent e = _ViewportEvents[i];
        if (!sui3IsClick(e)) continue;
        float2 p = e.position * _Resolution.xy;
        [loop] for (int b = 0; b < count; ++b) {
            float4 r = rects[b];
            if (p.x >= r.x && p.x <= r.z && p.y >= r.y && p.y <= r.w) hit = b;
        }
    }
    return hit;
}

// The Y-direction contract and `sui3PublishPad` live in sui3_core.hlsli, not
// here: a state pass must be able to publish a pad value without declaring
// viewport events, and including this header would drag in `_ViewportEvents`
// bindings it never declared. `au_text.hlsli:9` records the v1 kit failing to
// compile for precisely that reason.

#endif
