---
type: state
updated: 2026-07-30
---

# Workspace State

## Current focus

Phase 6 has produced the curated public-workspace release candidate. The project
set, manuals, knowledge, skills, promotion rails, and release audits are
complete locally. Public push authorization remains pending at Human Gate G13.

## Curated seed

The distributable project lineup is:

- `autopsia`
- `camera_reference`
- `cloth_lab`
- `face_collage`
- `industrial_lattice`
- `interaction_lab`
- `living_room_sdf`
- `scientific_organism`
- `strata`
- `streamdiff_canvas`
- `streamdiff_workflows`
- `touchdesigner_new_project`

`showcase_gallery` remains tracked as a review-only internal collection and is
explicitly refused by the promotion tool.

The public entry manuals (`AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`) are
byte-identical. The workspace contains 20 knowledge documents and mirrored
`.agents/skills` / `.claude/skills` trees.

## Validation

The release candidate passes:

- `tools/validate-official-examples.ps1`: 13 passed, 0 failed.
- `tools/audit-public-release.ps1`: exact project set, synchronized manuals and
  skill mirrors, tracked-secret scan, Markdown links, file-size thresholds,
  asset/license coverage, and Sentinel version/capability compatibility.
- `tools/plan-public-release.ps1`: exact-set release plan with no unexpected
  project directory.

Run `git rev-parse HEAD` to identify the candidate being tested. A valid agent
test checkout must report no output from `git status --short`.

## Asset status

The two external media inputs in the curated seed are recorded and cleared:

- `projects/streamdiff_workflows/assets/dancer_vert.mp4`
- `projects/touchdesigner_new_project/images/jellybeans.png`

Living Room SDF is fully procedural. Seven duplicated, unreferenced legacy
photo/video files were removed during release packaging.

## Blockers

There are no known content, portability, link, secret, file-size, or asset-rights
blockers in the local candidate.

The public remote still represents the previous release. No push, tag, or
release is authorized until the user explicitly approves G13 after reviewing
the complete clean-checkout candidate.

## Last devlog

`docs/devlogs/2026-07-30-phase-6n-public-seed-release-candidate.md` records the
release assembly and clean-checkout verification.
