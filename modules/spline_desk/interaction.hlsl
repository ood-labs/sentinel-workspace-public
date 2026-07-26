// Spline Desk - event reduction.
//
// Rebuilt from v1's interaction pass. The command vocabulary, EditorState
// layout and downstream passes are unchanged, because those are the contract
// Spline_Output consumes. Two things are different, and both are defects fixed
// rather than preferences changed:
//
//  1. HIT TESTING IS ASPECT-CORRECT. v1 compared normalized distances against a
//     flat 0.022, so the pick region was a circle only when the panel happened
//     to be square-ish. On the 1920x403 dock this station now has to survive,
//     0.022 normalized is 42px across and 9px tall -- you could not grab a
//     handle without also grabbing its neighbour. Distances are now measured in
//     PIXELS against a parameter, which is what CLAUDE.md's coordinate
//     discipline asks for.
//
//  2. EVERY ACTION HAS A BOOL DOOR. The button controls stay and are read
//     through the control-flags `down` bit, never through the `type: button`
//     parameter global that 3C measured as a one-way latch. Alongside them, four
//     bool parameters fire the same commands on a rising edge so the actions can
//     be driven by OSC, a Conductor cue, an expression -- or by a proof script,
//     which matters because no MCP call can click inside a module preview.
#include "types.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"

StructuredBuffer<SplineKnot> _Tex0 : register(t0);
RWStructuredBuffer<EditorState> OutputBuffer : register(u0);

int nextActive(uint splineId, int after) {
    [loop] for (int i = after + 1; i < 64; i++)
        if (_Tex0[i].active > 0.5 && _Tex0[i].spline_id == splineId) return i;
    return -1;
}

// `p` and the knot records are normalized; `aspect` converts a normalized delta
// into pixels so one radius means the same thing on every dock shape.
float2 toPx(float2 d, float2 R) { return d * R; }

void hitTest(float2 p, float2 R, float radiusPx,
             out int hitIndex, out int hitKind, out int hitSpline) {
    hitIndex = -1; hitKind = 0; hitSpline = -1;
    float best = radiusPx;
    [loop] for (int i = 0; i < 64; i++) {
        SplineKnot k = _Tex0[i];
        if (k.active < 0.5) continue;
        float d = length(toPx(p - k.anchor, R));
        if (d < best) { best = d; hitIndex = i; hitKind = 1; hitSpline = (int)k.spline_id; }
        d = length(toPx(p - k.handle_in, R));
        if (d < best) { best = d; hitIndex = i; hitKind = 2; hitSpline = (int)k.spline_id; }
        d = length(toPx(p - k.handle_out, R));
        if (d < best) { best = d; hitIndex = i; hitKind = 3; hitSpline = (int)k.spline_id; }
    }
    // Anchors and handles win over the curve body even when the curve is nearer,
    // because grabbing the line when you aimed at a point is the more annoying
    // of the two failures.
    if (hitKind != 0) return;

    [loop] for (uint spline = 0u; spline < 8u; spline++) {
        int a = nextActive(spline, -1);
        if (a < 0) continue;
        int b = nextActive(spline, a);
        [loop] while (b >= 0) {
            float2 prev = _Tex0[a].anchor;
            [loop] for (int s = 1; s <= 12; s++) {
                float t = (float)s / 12.0;
                float2 cur = cubicPoint(_Tex0[a].anchor, _Tex0[a].handle_out,
                                        _Tex0[b].handle_in, _Tex0[b].anchor, t);
                // Segment distance in pixel space, same reason as above.
                float d = pointSegmentDistance(p * R, prev * R, cur * R);
                if (d < best) { best = d; hitIndex = a; hitKind = 4; hitSpline = (int)spline; }
                prev = cur;
            }
            a = b; b = nextActive(spline, a);
        }
    }
}

[numthreads(1,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float2 R = _Resolution.xy;
    EditorState st = OutputBuffer[0];
    // MAGIC SENTINEL, not a range check on `tool`. v1 guarded on `tool` being
    // out of 0..1, but a zeroed buffer has tool = 0, which is valid -- so the
    // seed never ran and tangent_mode stayed 0 while the knots it describes
    // were created at mode 1. The desk reported FREE next to handles drawn
    // ALIGNED. A readout that disagrees with the thing it labels is worse than
    // no readout, so the guard now tests a value that cannot occur by accident.
    if (abs(st.toolbar_pad.x - SD_MAGIC) > 0.5 || isnan(st.tool)) {
        st.tool = 0.0; st.active_spline = 0.0; st.tangent_mode = 1.0;
        st.auto_latch = 0.0; st.toolbar_latch = 0.0;
        st.toolbar_pad = float2(SD_MAGIC, 0.0);
    }
    st.command = 0.0; st.phase = 0.0;

    // Tool comes from the ordinary int parameter, so the host owns it and it
    // undoes, presets and saves like any other value.
    st.tool = clamp((float)tool_mode, 0.0, 1.0);

    // --- toolbar: control-flag down bits, edge-detected --------------------
    uint down = (suiInteraction(UI_INDEX_TANGENT).down ? 1u : 0u)
              | (suiInteraction(UI_INDEX_CLOSE).down   ? 2u : 0u)
              | (suiInteraction(UI_INDEX_DELETE).down  ? 4u : 0u);
    uint pressed = down & ~(uint)round(st.toolbar_latch);
    st.toolbar_latch = (float)down;

    // --- automation: bool parameters, edge-detected against the same latch --
    uint autoNow = (do_tangent   > 0.5 ? 1u : 0u)
                 | (do_close     > 0.5 ? 2u : 0u)
                 | (do_delete    > 0.5 ? 4u : 0u)
                 | (do_next_lane > 0.5 ? 8u : 0u)
                 | (do_undo      > 0.5 ? 16u : 0u)
                 | (do_select_lane > 0.5 ? 32u : 0u)
                 | (do_clear_sel   > 0.5 ? 64u : 0u)
                 | (do_reset      > 0.5 ? 128u : 0u)
                 | (do_nudge      > 0.5 ? 256u : 0u);
    uint autoFired = autoNow & ~(uint)round(st.auto_latch);
    st.auto_latch = (float)autoNow;

    uint fire = pressed | autoFired;
    if ((fire & 1u) != 0u) { st.tangent_mode = fmod(st.tangent_mode + 1.0, 3.0); st.command = 8.0; }
    if ((fire & 2u) != 0u) st.command = 7.0;
    if ((fire & 4u) != 0u) st.command = 9.0;
    if ((autoFired & 8u) != 0u) st.active_spline = fmod(st.active_spline + 1.0, 8.0);
    // Command 4 is v1's cancel/restore-from-snapshot. It is what Escape already
    // did, and it is exactly "put the knots back the way the snapshot has them",
    // so the automation door reuses it rather than inventing a second path.
    if ((autoFired & 16u) != 0u) { st.command = 4.0; st.phase = 8.0; }
    if ((autoFired & 32u) != 0u) st.command = 10.0;
    if ((autoFired & 64u) != 0u) st.command = 11.0;
    if ((autoFired & 128u) != 0u) st.command = 12.0;
    if ((autoFired & 256u) != 0u) st.command = 13.0;

    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint i = 0u; i < count; i++) {
        ViewportEvent e = _ViewportEvents[i];
        if (e.type == 4u && e.phase == 1u) {
            if (e.code == 22u) st.tool = 0.0;                                                  // V
            if (e.code == 16u) st.tool = 1.0;                                                  // P
            if (e.code == 20u) { st.tangent_mode = fmod(st.tangent_mode + 1.0, 3.0); st.command = 8.0; } // T
            if (e.code == 15u) st.command = 7.0;                                               // O
            if (e.code == 52u) st.command = 9.0;                                               // Backspace
            if (e.code == 50u) st.active_spline = fmod(st.active_spline + 1.0, 8.0);           // Enter
            if (e.code == 48u) { st.command = 4.0; st.phase = 8.0; }                           // Escape
        }

        // A pointer boundary inside the authored toolbar must never leak through
        // as a canvas edit on the same frame. The band is derived from the
        // toolbar's own rect, not a hard-coded 0.12 as in v1, so moving the
        // toolbar cannot silently move the dead zone.
        if (e.type == 5u && e.device == 0u && e.position.y < UI_RECT_TOOL.w) continue;

        if (e.type == 5u && e.code == 2u && e.phase == 4u)
            st.active_spline = fmod(st.active_spline + 1.0, 8.0);

        if (e.type == 5u && e.code == 1u && e.phase == 7u && st.tool > 0.5) {
            st.command = 5.0; st.pointer = e.position; st.modifiers = (float)e.modifiers;
        }

        if (e.type != 5u || e.code != 3u || e.device != 0u) continue;

        if (e.phase == 5u) {
            int hitIndex, hitKind, hitSpline;
            hitTest(e.position, R, hit_radius, hitIndex, hitKind, hitSpline);
            st.command = 1.0; st.phase = 5.0;
            st.target = (float)hitIndex;
            st.target_kind = (float)(hitKind == 0 ? 5 : hitKind);
            st.active_spline = hitSpline >= 0 ? (float)hitSpline : st.active_spline;
            st.drag_start = e.position; st.pointer = e.position;
            st.marquee_start = e.position; st.marquee_end = e.position;
            st.modifiers = (float)e.modifiers;
        } else if ((e.phase == 6u || e.phase == 7u || e.phase == 8u) && st.target_kind > 0.0) {
            // The handle acquired on pointer-down is retained until commit or
            // cancel; the target is never re-picked mid-drag, so a fast flick
            // cannot drop the edit onto a different knot.
            st.command = e.phase == 8u ? 4.0 : (e.phase == 7u ? 3.0 : 2.0);
            st.phase = (float)e.phase;
            st.pointer = e.position;
            st.marquee_end = e.position;
            st.modifiers = (float)e.modifiers;
        }
    }
    // Latch the last non-zero command so the desk can be diagnosed from a
    // control output instead of by inference. A command vocabulary you cannot
    // observe is a command vocabulary you cannot debug.
    // ---- arm-then-execute -------------------------------------------------
    // `st.command` up to this point is what this cook WANTS to happen. Edits
    // that undo must be able to reverse are armed instead of run, so the next
    // cook executes them while THIS cook -- which mutates nothing -- is the one
    // the snapshot pass captures on.
    float want = st.command;
    bool needsSnap = (want == 1.0 || want == 5.0 || want == 7.0
                   || want == 8.0 || want == 9.0 || want == 12.0
                   || want == 13.0);
    float exec = 0.0;
    if (st.pending > 0.5) { exec = st.pending; st.pending = 0.0; }
    if (want > 0.5) {
        if (needsSnap) { if (exec < 0.5) st.pending = want; }
        else exec = want;   // drag moves, undo and selection run the same cook
    }
    st.command = exec;
    if (exec > 0.5) st.last_cmd = exec;
    OutputBuffer[0] = st;
}
