---
type: devlog
date: 2026-07-26
session_start: "18:06"
session_end: "18:30"
phase: 3
subphase: 3F
status: complete
approval: pending
updated: 2026-07-26
summary: "Audit round three: a fix from round two was corrupting drags and shipped green through 42 guards. Split the arm flag, fixed two gizmo deferred-cook defects, made the hands-on recorder fail closed, corrected two overstated amendments."
---

# Phase 3 - Audit Round Three

Session record for the third audit round on Phase 3. The phase boundary itself is
[[2026-07-27-phase3-close-out]], which carries a summary of this work; this entry is the detailed
record of what was found and changed.

## Goal

Act on the round-two audit reports, which arrived at the end of the previous session and were not
yet applied. Verify each finding before touching it. Do not approve the phase.

## Work done

**The ship-blocking finding was a regression I introduced in the previous round.** The round-two fix
made `spline_desk` queue a command rather than drop it, and queued it in `pending`, the field that
already meant "armed, undo snapshot still needed". Those are two different facts, and a live drag
separates them on every frame: cook *k* drains `pending` into `exec`, the next pointer move arrives
while `exec` is busy, `pending` is written again, forever. `snapshot.hlsl` gated on `pending` alone,
so it re-captured the drag base every cook. `update.hlsl:36-49` computes
`base = drag_snapshot[i] + (pointer - drag_start)` with `drag_start` frozen at pointer-down, so an
advancing base puts the knot at `base0 + sum(deltas)`. The drag accelerates away from the cursor and
the pre-drag undo point is destroyed. Traced through the update pass before editing anything; the
result holds under either scheduler order, so it does not depend on the earlier pass-order
measurement.

Fixed by splitting the two facts. `armed` (`modules/spline_desk/types.hlsli`) is set only on a cook
where a command is queued **and** nothing is executing; the snapshot reads that instead. Splitting
them exposed a second defect the shared field had been hiding: a structural edit that arrived during
a busy cook drained straight into execution with no snapshot ever taken, so that edit was silently
unundoable. It now goes round again and arms properly on a clean cook.

**Two `gizmo_desk` defects, both on the cook a deferred command runs.** The transaction source was
resynced to the live selection because `dragging` and `drag_pad.z` are both clear by then, so a
deferred commit landed on whatever the host's release-pick had selected; the resync is now suppressed
while `pending` is set. And a newcomer could supersede a deferred **commit** - the "a drag move is
idempotent" reasoning is true for a deferred 2 and false for a 3 or 4. For the same-cook
begin-and-commit that deferral exists to serve, the deferred 3 *is* the transform, so dropping it
means the object never moves at all. Finalizers now run on time and push the newcomer back a cook.

**Observability, because this mechanism has now failed twice while invisible from outside the
shader.** `pending_command` and `snapshot_armed` are published as control outputs and a guard asserts
the arm latch clears. A latched arm is the silent form of the drag bug: the snapshot re-captures the
current knots every cook, so undo restores the desk to exactly where it already is while geometry,
readouts and health all look correct.

**Tooling.** The hands-on recorder's door poison failed open - a state read that threw left
`doors = False`, silently disabling the one gate that stops a door-driven change being credited as a
hand on the mouse, precisely when a wrong answer is most likely. It now taints and records why. A
guard that raised used to abort the whole run and leave every later guard producing no line at all,
which reads as a clean short run; each guard is now wrapped.

**Two amendments were overstated and are corrected in place.** Amendment 5 called numeric orbit "the
only code-path-identical proxy" for the drag transform. It is a separate early-returning branch
(`modules/gizmo_desk/update.hlsl:39-64`) that averages its own pivot from `OutputBuffer`, uses world
axes only, and takes its angle from a parameter, while the drag path uses the captured pivot,
local-space axes, a pointer-derived angle and the snapshot as base. Amendment 7 said the orphaned v1
directories were "referenced by no project, manifest or document"; four files reference them.

Smaller: the 3C devlog summary still asserted the retracted causal speedup; the 3C.5 criterion still
instructed the retired inversion; 3B's frontmatter said `complete` while its gesture criterion is
open, like 3D and 3E; the amendment block gained an index because Amendment 2 lives in the 3B section
and the sequence looked to have a hole. `docs/state.md` carried an inherited note that the host
`xypad` stores Y increasing downward, which is wrong and cost three operator reports of the same
defect; corrected with the measurement.

## Decisions made

- **Split the field rather than tighten the gate.** Gating the snapshot on `pending > 0.5 && command
  < 0.5` would have fixed the drag, but it would have left the queued-behind-busy edit executing
  without a snapshot. A named `armed` flag fixes both and makes the invariant readable.
- **Removed the 5/6 mapping in `gizmo_desk/update.hlsl` rather than leaving it as defensive code.**
  It is unreachable now, and if a 5 ever did reach that pass it would transform against a stale
  snapshot - the exact bug deferral exists to prevent. Falling through the range check is a visibly
  dropped gesture instead, which is the safer failure.
- **Kept `7321.0` as a literal in the guard rather than reading it from the shader header.** A guard
  that reads its expected value from the thing it checks passes whatever that thing says. That is
  how four pad surfaces once agreed with each other while all four were upside down.
- **Amendments corrected in place with a dated correction note, not rewritten.** The original wording
  and the reason it was wrong are both worth keeping.
- **Phase 3 is NOT approved.** `approval: pending` throughout.

## Issues encountered

- The regression shipped **green through the entire 42-guard suite**, and no guard could have caught
  it: no automated call can drive a pointer, and the defect only manifests during a sustained drag.
  The new arm-latch guard catches the residue, not the event.
- The manifest edit invalidated `_ui.generated.hlsli` and the bundle-identity guard caught it as a
  stale-header FAIL. Regenerating with `module-ui.ps1 generate` and re-syncing fixed it. `pwsh` is not
  on PATH here; the script also needs the call operator (`& "<abs path>"`) because
  `powershell -File <relative>` leaves `$PSScriptRoot` empty and the script dies on `Split-Path`.
- Rewriting a Python file with a script normalised its line endings; `git diff --stat` confirmed only
  the intended lines changed rather than the whole file.

## Verification

- `python tools/interaction-lab-guards.py`: **42 passed, 0 failed, 4 skipped** (was 39/0/4). The four
  skips are unchanged and are the hands-on gap.
- The guard-exception wrapper was proven by running a deliberately throwing guard through it and
  confirming it recorded a FAIL rather than aborting.
- `compile_check` clean on `spline_desk`, `gizmo_desk`, `motion_console`; all three `force_reload`ed
  to `state: ok` and re-verified live.
- Graph profile: five stations healthy, 60 Hz cook, no hotspots.

## Next steps

The operator hands-on gesture pass, then approval. **Five unguarded fixes now rest on it**, not the
three criteria it was scoped for. While dragging, two symptoms are worth watching for that no guard
can see: an object that accelerates away from the cursor rather than tracking it, and undo
immediately after a drag failing to restore the pre-drag position.

## Cross-references

- [[phase-3-interaction-lab-v2]] - the contract, Amendments 5 and 7 corrected here
- [[2026-07-27-phase3-close-out]] - the phase boundary record
- [[2026-07-26-phase3d-spline-desk]], [[2026-07-26-phase3e-gizmo-desk]] - the stations changed here
- [[lessons]] - "One flag for two facts"
