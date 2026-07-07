---
type: implementation-plan
updated: 2026-07-07
---

# Implementation Plan

Top-level phase index for this workspace's dev-system. (Distinct from the Sentinel app repo's
own phase numbers referenced in `knowledge/`.)

## Phase Overview

| Phase | Title | Status | Detail |
| --- | --- | --- | --- |
| 1 | Reference Rebuilds (11 clips) | planned | [phase-1-reference-rebuilds.md](phases/phase-1-reference-rebuilds.md) |

## Phase 1 — Reference Rebuilds

Faithfully recreate all 11 reference clips in `refs/try_v20260706_2246/` as modular Sentinel
scenes, reference-image-driven and silhouette-first, per `knowledge/reference-rebuild-guide.md`.
Driven autonomously by a `/slash-goal` loop; calibration on clip C1 with full stage checkpoints,
then self-verified with final sign-off per clip.

- **Deliverables:** 11 clip scenes (C1–C11), each = per-clip Definition of Done (silhouette +
  composition + material + seamless-loop motion match, harvested). See the phase doc's deliverables
  table for the clip list, technique lanes, and biting pass criteria.
- **Governing spec / method:** `knowledge/reference-rebuild-guide.md`.
- **Key tools:** Sentinel MCP (`module`/`conductor`/`mux`/`atlas`, `sentinel_blueprint`,
  `sentinel_conductor`), `modules/_shared/{sdf,anim}`, `vision-eval` MCP, ffmpeg.
- **Order:** C1 (calibration) → C2 … → C11 (hardest); the three under-decomposed clips are
  re-studied before building.
- **Autonomy:** see the phase doc's Autonomy section (gate tiers, pre-authorizations, hard blockers).

### Future phases
None planned yet. Candidate follow-ups: a second reference batch; harvesting the rebuild techniques
into a reusable "reference-rebuild" toolkit.
