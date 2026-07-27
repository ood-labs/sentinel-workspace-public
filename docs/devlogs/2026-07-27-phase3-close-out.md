---
type: devlog
date: 2026-07-27
phase: 3
subphase: close-out
status: complete
approval: pending
summary: "Phase 3 close-out: operator-reported pad and caption defects fixed, two audit rounds landed, 3F closed, planning docs brought current. Phase held open by the hands-on gesture pass."
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

**Two audit rounds.** The first round's ship-blockers were two dropped-command defects, both traced
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

## Next steps

The hands-on gesture pass, then approval. It now retires two unguarded fixes as well as three
criteria, because a spline anchor drag is exactly the pointer-down-then-drag-move sequence that
produced the dropped SELECT, and a gizmo axis drag is the begin-and-move-in-one-cook path.

## Cross-references

- [[phase-3-interaction-lab-v2]] - the contract, now carrying Amendments 1-7
- [[2026-07-26-phase3f-consolidation]] - the full narrative for this work
- [[2026-07-26-phase3d-spline-desk]], [[2026-07-26-phase3e-gizmo-desk]] - both `in-progress`
  pending the gesture pass
