---
type: devlog
date: 2026-07-27
phase: 3
subphase: close-out
status: complete
approval: pending
summary: "Phase 3 close-out: operator-reported pad and caption defects fixed, three audit rounds landed including a self-inflicted drag-corruption regression, 3F closed, planning docs brought current. Phase held open by the hands-on gesture pass."
---

# Phase 3 Close-Out

Session record for the Phase 3 close attempt. The substance lives in the sub-phase devlogs; this
entry is the boundary record and the handover. The detailed narrative for everything below is in
[[2026-07-26-phase3f-consolidation]].

## Goal

Close Phase 3 end to end: resolve the operator's reported defects, act on the audit findings, close
3F, and run the phase boundary.

## Work done

**Operator-reported defects, all three fixed and verified live.**

The Style Authority pad's Y was reversed against the Properties widget. It had been reported once
before and "fixed" wrongly: that fix made the module's four surfaces agree with each other while all
four stayed upside down against the host row, which the module does not draw and had never been
compared against. The host's XY pad is Y-up. Value-to-pixel now goes through one kit function,
`sui3PadPoint`, with `sui3PadValue` as its inverse. Measured at both ends on both pads: value 0.9
draws at 0.90 of the well from its bottom, 0.1 at 0.10.

PUBLISHED, METERS and PRIMITIVES rendered at double the page title's height. The title gives back
size when the header band is thin; section scale had no such give-back, so the type hierarchy stood
on its head. Section is now clamped to title. Separately PUBLISHED advanced by the body line height
while drawing at section scale, putting the table frame through its own caption.

**Three audit rounds.** The first round's ship-blockers were two dropped-command defects, both traced
by hand before being touched. `spline_desk` discarded a command instead of queueing it, so a
pointer-down SELECT was overwritten by the drag move that followed and the drag moved the previous
selection. `gizmo_desk` never adopted arm-then-execute and hit the `snapshot`/`update` read-write
cycle `spline_desk` had already measured, transforming against the previous transaction's snapshot.
Four smaller fixes: the gizmo reseed sentinel, the 80-vs-96 byte schema, a missing click-phase
filter, and two float guards in the raymarcher.

**The Style Authority now governs something.** Deliverable D3's entire justification was proven in
3B against a module 3F deleted, leaving the shipped project with zero expressions. Nine drivers now
run the other three stations' accent from the authority, saved into the project and asserted on the
causal chain.

**Documentation.** Amendments 5, 6 and 7 record the numeric-transform fence crossing, retire
"flipped exactly once" as unfalsifiable wording, and record two orphaned v1 module directories.
Amendment 1 carries a SUPERSEDED marker; Amendment 2 was promoted out of a run-in. Verification Plan
criterion numbers corrected. 3D and 3E returned to `in-progress`, which the phase doc requires while
their gesture criterion is open. `docs/state.md` and `docs/implementation-plan.md` brought current
after six stale devlogs.

## Decisions made

- **Numeric transform entry stays**, recorded as a deviation rather than reverted. It is the only
  code-path-identical proxy the gizmo has for its transform maths, and 3E.2 is proven through it.
- **The two orphaned v1 module directories stay** for the operator to decide. Deleting tracked
  source is not an audit-fix decision, and they are the only remaining reference for behaviours 3D
  and 3E claim to preserve.
- **The `derive.hlsl` empty-lane sentinel and the orbit door's edge consumption were considered and
  rejected** as changes. Both are correct as written.
- **Phase 3 is NOT approved.** `approval: pending` throughout.

## Issues encountered

- A guard written for the spline queueing fix does not test it. Reverting the fix and recompiling
  produced PASS. MCP round trips are slower than a 16 ms cook, so fired commands never collide.
  Recorded rather than quietly kept.
- Two bugs in the new guards themselves: `do_reset` reseeds to fixed anchors rather than restoring
  prior state, and the gizmo state buffer reads zero for one cook after the host recreates it.
- The hands-on recorder credited three gestures with nobody at the mouse on its first run. Three
  gates added; re-running the same door sequence now records zero and stamps the record tainted.
- **A fix landed in the first audit round was worse than the defect it fixed**, and shipped green
  through a 42-guard suite. Detail under the round-two section below. The reusable part is in
  [[lessons]]: `pending` was made to carry two facts that a live drag separates on every frame.

## Post-landing audit round two

Three parallel agents (code / spec / test) audited the work above. The headline finding was mine:
**the first round's queueing fix introduced a worse defect than the one it fixed.**

`spline_desk` had been dropping a command; the fix queued it instead. But it queued it in `pending`,
the same field that means "armed, snapshot still needed", and on a live drag that field is rewritten
every cook. The snapshot pass gated on `pending` alone, so it re-captured the drag base every frame
while `drag_start` stayed frozen at pointer-down. The knot lands at `base0 + sum(deltas)`: the drag
accelerates away from the pointer and the undo point is gone. Traced through `update.hlsl:36-49`
before touching anything, and it holds under either scheduler order.

Fixed by splitting the two facts apart. `armed` is set only on a cook where a command is queued and
nothing is executing; the snapshot reads that. Splitting them exposed a second defect the shared
field had been hiding: a structural edit that arrived during a busy cook executed with **no snapshot
taken at all**, so that edit was silently unundoable. It now gets its own arm cook.

Two more in `gizmo_desk`, both on the cook a deferred command runs. The transaction source was being
resynced to the live selection because `dragging` and `drag_pad.z` are both clear by then, so a
deferred commit landed on whatever the host's release-pick had selected. And a newcomer could
supersede a deferred **commit**, which for the same-cook begin-and-commit that deferral exists to
serve means the object never moves at all. Commits and cancels now run on time and push the newcomer
back a cook. The unreachable 5/6 mapping in `update.hlsl` was removed rather than left as a trap that
would quietly restore the stale-snapshot bug.

**Observability, because this mechanism has now failed twice while being invisible.** `pending_command`
and `snapshot_armed` are published as control outputs, and a guard asserts the arm latch clears. A
latched arm is the silent form of the drag bug: the snapshot re-captures every cook, so undo restores
the desk to exactly where it already is while geometry, readouts and health all look correct. The
guard cannot reach the mid-drag re-arm itself, and says so.

**Two amendments were overstated and are corrected in place.** Amendment 5 called numeric orbit "the
only code-path-identical proxy" for the drag transform. It is not the same code path: command 20 is a
separate early-returning branch that averages its own pivot from `OutputBuffer`, uses world axes only,
and takes its angle from a parameter, while the drag path uses the captured pivot, local-space axes,
pointer-derived angle and the snapshot as base. They share `rotateAround` and an idea. So 3E.2 proves
less than was claimed. Amendment 7 said the orphaned v1 directories were "referenced by no project,
manifest or document"; they are referenced by `.sentinel-workspace-manifest.json`,
`knowledge/ui-authoring.md`, and the `module-ui-authoring` skill in two places, so removal is a
four-file change, not two deletions.

Smaller: the hands-on recorder's door poison failed open, so a state read that threw silently
disabled the one gate stopping a door-driven change being credited as a hand on the mouse; it now
taints and records why. A raising guard used to abort the run and leave every later guard producing
no line at all, which reads as a clean short run; each guard is now wrapped, proven by watching a
deliberately throwing guard record a FAIL. The 3C devlog's summary still asserted the retracted
causal speedup. The 3C.5 criterion still instructed the retired inversion. 3B's frontmatter said
`complete` while its gesture criterion is open, like 3D and 3E; it is now `in-progress`. An index
was added for the amendment block, since Amendment 2 lives in the 3B section and the sequence looked
to have a hole.

Considered and rejected: DRY-ing the `7321.0` sentinel out of the guard into the shader header. A
guard that reads its expected value from the thing it checks passes whatever that thing says, which
is exactly how four pad surfaces once agreed with each other while all four were upside down. It is
named once in the guard and stays an independent literal.

Guards: **42 passed, 0 failed, 4 skipped.** The four skips are unchanged and are the hands-on pass.

## Next steps

The hands-on gesture pass, then approval. It has become the only way to retire more than the three
criteria it was scoped for. A spline anchor drag is the pointer-down-then-drag-move sequence that
produced the dropped SELECT **and** the sustained-drag path where the snapshot re-armed every cook;
neither has an automated guard, and the second one shipped green. A gizmo axis drag is the
begin-and-move-in-one-cook path plus the deferred-commit cases fixed in round two. Five unguarded
fixes now rest on it.

The operator should watch specifically for a drag that lags or accelerates away from the cursor
rather than tracking it, and should press undo immediately after a drag to confirm the pre-drag
position comes back. Those are the two symptoms the round-two regression produced.

## Cross-references

- [[phase-3-interaction-lab-v2]] - the contract, now carrying Amendments 1-7
- [[2026-07-26-phase3f-consolidation]] - the full narrative for this work
- [[2026-07-26-phase3d-spline-desk]], [[2026-07-26-phase3e-gizmo-desk]] - both `in-progress`
  pending the gesture pass
