// Style Authority - viewport event reduction.
//
// Turns the pad, toggle and bank from pictures of values into actual controls.
// Before this pass existed the sheet drew three things that look exactly like
// controls and ignored every click, which is precisely what CLAUDE.md forbids:
// "do not add ... decorative controls merely to make a composition appear
// interactive." Caught at the 3B taste checkpoint by someone trying to click
// the pad.
//
// This is also the first exercise of the event ABI documented in
// sui3_events.hlsli. 3C's burst hit-test, 3D's spline drag and 3E's gizmo
// select all depend on that ABI being right, so proving it here -- on the
// simplest possible surface -- is deliberate de-risking.
//
// UI[0] = (pad_x, pad_y_raw, toggle, bank)   pad_y_raw is DOWN=more, host
//                                            convention; the flip to up=more
//                                            happens once, at publish, in
//                                            state.hlsl
// UI[1] = (initialised, events_seen, 0, 0)   events_seen is a live diagnostic,
//                                            published so a reader can tell
//                                            "no events arrived" apart from
//                                            "events arrived and missed"
#include "layout.hlsli"
#include "../_shared/ui/sui3_events.hlsli"

RWStructuredBuffer<float4> UI : register(u0);

// Distinctive enough that stale memory will not impersonate it.
static const float SA_UI_MAGIC = 7331.0;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 s = UI[0];
    float4 d = UI[1];
    float4 last = UI[2];

    // The Properties values, packed the same way as the live state.
    float4 p = float4(saturate(demo_pad.x), saturate(demo_pad.y),
                      demo_toggle > 0.5 ? 1.0 : 0.0,
                      (float)clamp(demo_bank, 0, 3));

    // Seed from the Properties values on the first frame so the control has a
    // sane pose before anyone touches it, and so a param edit is still the way
    // to set an exact value.
    //
    // The guard is a MAGIC SENTINEL, not `d.x != 0`. A persistent buffer is not
    // documented as zero-initialised, and a stale allocation whose first float
    // happens to be nonzero would skip the seed and leave the control in a
    // garbage pose -- a bug that looks like "the pad jumps somewhere random
    // after reload" and is miserable to trace back to here. au_stylus guards
    // the same way with a CTRL_INIT flag plus an isnan check.
    if (abs(d.x - SA_UI_MAGIC) > 0.5 || isnan(s.x) || isnan(s.y)) {
        s = p;
        d = float4(SA_UI_MAGIC, 0.0, 0.0, 0.0);
        last = p;
    }

    // PROPERTIES EDITS MUST STILL WIN. Making the persistent buffer the source
    // of truth silently killed the parameters: they seeded frame one and were
    // ignored forever after. That broke two things at once -- the promise that
    // Properties sets an exact value, and every `capture_at` override, which is
    // the mechanism 3C-3E use for automated proof. Caught by diffing a capture
    // whose overrides had no effect.
    //
    // Comparing against the LAST-SEEN parameter value, not against the live
    // state, is what makes this work in both directions: a pointer drag moves
    // `s` away from `last` without looking like a param edit, while an actual
    // param edit moves `p` away from `last` and takes over.
    if (any(abs(p - last) > 1e-5)) {
        s = p;
        last = p;
    }

    SaLayout L = saLayout(_Resolution.xy, title_scale, section_scale,
                          outer_padding, section_gap, control_height, control_gap);

    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; ++i) {
        ViewportEvent e = _ViewportEvents[i];

        bool click = (e.type == 5u && e.code == 1u);
        bool drag  = (e.type == 5u && e.code == 3u && e.phase != 8u);
        if (!(click || drag)) continue;

        d.y += 1.0;

        // e.position is normalised IMAGE space, so it maps straight onto the
        // canonical render extent. au_stylus relies on the same contract.
        float2 p = saturate(e.position) * L.R;

        // The pad accepts click AND drag: a pad you can only click is a worse
        // control than a slider. Everything else is click-only, because
        // dragging across a bank should not scrub through four selections.
        if (saHit(p, L.rPad, 2.0)) {
            float2 inner = float2(L.rPad.z - L.rPad.x, L.rPad.w - L.rPad.y);
            s.x = saturate((p.x - L.rPad.x) / max(inner.x, 1.0));
            s.y = saturate((p.y - L.rPad.y) / max(inner.y, 1.0));
            continue;
        }

        if (!click) continue;

        if (saHit(p, L.rTog, 3.0)) {
            s.z = (s.z > 0.5) ? 0.0 : 1.0;
            continue;
        }

        [loop] for (int b = 0; b < 4; ++b) {
            if (saHit(p, saBankCell(L, b), 2.0)) { s.w = (float)b; break; }
        }
    }

    UI[0] = s;
    UI[1] = d;
    UI[2] = last;
}
