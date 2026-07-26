// Spline Desk - pre-edit snapshot, the buffer that undo restores from.
//
// v1 captured ONLY on command 1 (drag begin), because the only thing it could
// undo was a drag. That made "delete a knot, then undo it" impossible: the
// snapshot still held whatever the last drag started from, or zeros if no drag
// had ever happened, so undo after a delete restored an empty desk. Measured,
// not assumed -- the 3D probe showed active 4 -> 0 on delete and then 0 -> 0 on
// undo.
//
// The snapshot now captures before every STRUCTURAL edit, which makes undo a
// real one-step undo for all of them. Mid-drag commands (2, 3) are excluded so
// a drag keeps the state it started from rather than resampling itself every
// frame, and the restore command (4) is excluded so undo cannot overwrite the
// thing it is about to read. Selection commands (10, 11) are excluded too: a
// selection change should not consume the undo slot and cost you the edit you
// actually wanted back.
#include "types.hlsli"
StructuredBuffer<EditorState> _Tex0 : register(t0);
StructuredBuffer<SplineKnot> _Tex1 : register(t1);
RWStructuredBuffer<SplineKnot> OutputBuffer : register(u0);

// MEASURED CORRECTION. Capturing ON the command frame does not work, and the
// reason is the pass graph, not the logic: `snapshot` reads spline_knots and
// `update` writes it, while `update` reads drag_snapshot and `snapshot` writes
// it. That is a cycle, and the scheduler resolves it by running `update` first
// -- so a snapshot taken on the command frame records the state AFTER the edit
// and undo restores the desk to exactly where it already is. Proven with a
// last_command control output: undo emitted command 4 every time and the
// tangent stayed at the edited value.
//
// v1 never saw this because it captured only on drag-begin, where nothing has
// moved yet and post-update happens to equal pre-drag. The accident does not
// survive discrete edits.
//
// A continuous mirror that freezes during the edit does not work either: the
// first idle cook after the edit re-mirrors the post-edit state, collapsing the
// undo window to a single cook. Also measured.
//
// So the edit is ARMED one cook before it runs, and the snapshot captures on the
// arm cook and only then. On that cook `pending` names the edit
// that will run next cook and `command` is zero, so nothing has mutated yet and
// spline_knots still holds the pre-edit state no matter which order the
// scheduler picked. Between edits the snapshot is left alone, so the undo state
// survives until the next edit arms -- a continuous mirror does not, because
// the first idle cook after an edit overwrites it and the undo window collapses
// to a single cook.
[numthreads(1,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (_Tex0[0].pending < 0.5) return;
    [loop] for (uint i = 0u; i < 64u; i++) OutputBuffer[i] = _Tex1[i];
}
