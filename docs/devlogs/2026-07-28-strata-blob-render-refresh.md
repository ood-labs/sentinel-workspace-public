---
type: devlog
status: complete
session_start: "05:30"
session_end: "06:19"
phase: maintenance
subphase: strata-blob-render
approval: pending
summary: "Refresh Strata blob rendering with native camera and scalable SDF quality"
note_created: 2026-07-28
updated: 2026-07-28
---

# Strata Blob Render Refresh

## Goal

Modernize Strata's old blob renderer camera contract, expose practical SDF
quality controls, and restore a live editing path near 60 FPS.

## Work Done

- Replaced the shader-local orbit camera with Sentinel's native internal Fly
  camera and inverse-view-projection ray construction.
- Added Draft, Performance, Fidelity, and Custom quality modes.
- Added Custom controls for march steps, part budget, march distance, surface
  epsilon, step scale, normal epsilon, AO samples, shadow steps, and AA.
- Added quality-aware marching and normal reconstruction so the new controls
  affect actual SDF traversal and surface precision.
- Bounded blob evaluation by quality tier and terminated packed active-first
  record scans at the inactive tail.
- Proved the renderer compiles cleanly, remains healthy, responds visibly to a
  deliberately reduced Custom configuration, and returns to 60 Hz in the saved
  Draft 480 x 720 state.

## Decisions Made

- Keep the internal Fly camera as the renderer's default owner; no external
  camera node is justified for this single 3D renderer.
- Save Draft at 480 x 720 as the live-performance state.
- Preserve Fidelity as the full 128-part, high-step option and expose every
  underlying cost/precision control through Custom.
- Treat the packed active-first `BlobPart` layout as a performance contract for
  the renderer's early-exit loops.

## Approvals & Locks

- The operator approved the optimized look and requested the fast state be
  retained.
- The measured target is the 60 Hz live Draft path; higher tiers intentionally
  trade cadence for surface and lighting quality.

## Issues Encountered

- At 720 x 1080 in Performance mode the graph ran near 24 Hz, while bypassing
  Blob Render immediately restored 60 Hz, isolating GPU SDF work as the cause.
- The data input advertises 128 records even though active records are packed
  at the front. Scanning the inactive tail inside every march, normal, AO, and
  shadow sample wasted most of the shader's evaluation budget.
- A profile taken after structural hot reload initially looked like a
  regression because the live node was at Performance 720 x 1080. Reapplying
  the approved Draft 480 x 720 state measured 61 cooks/s at 11.45 ms total.

## Next Steps

- Use Draft for live camera work and switch to Performance or Fidelity only for
  captures that justify the added cost.
- If the authored layout grows beyond 32 active parts, verify its active-first
  packing contract before raising the Performance part budget.

## Cross-References

- [[2026-07-27-strata-feature-downscale]]
- [[performance-proof]]
- [[internal-camera-template]]

