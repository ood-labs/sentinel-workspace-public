---
type: state
updated: 2026-07-30
---

# Workspace State

## Current focus

Phase 6 is in a corrective public-seed audit after an agent test proved that the
old candidate still exposed stale root Modules as apparent creative authority.
The content model is now project-owned: the curated projects and their bundled
dependencies are the seed. The exact staged index passes a clean disposable-repo
proof; the corrective commit and final manifest binding remain pending. Public
push authorization remains pending at Human Gate G13.

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

There is no root `modules/` catalog. Every saved Module path resolves inside its
own `projects/<project>/modules/` directory. `showcase_gallery`, stale
experimental Modules, and obsolete audio/gallery test tooling are not part of
the candidate.

The public entry manuals (`AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`) are
byte-identical. The workspace contains 20 knowledge documents and 11 validated,
mirrored `.agents/skills` / `.claude/skills`.

## Validation

The corrective working tree currently proves:

- `tools/validate-official-examples.ps1`: 12 passed, 0 failed; 73 active
  project-local Modules, zero shared-root dependencies, zero orphans, and zero
  absolute paths.
- Real Sentinel `compile_check`: all 15 Modules moved from root into
  Interaction Lab and Scientific Organism compile with zero lints.
- `tools/test-official-examples.ps1`: release-validator and promotion regression
  suite passes.
- `tools/audit-public-release.ps1`: expects exactly 12 projects and zero root
  Modules; the generated workspace manifest contains exactly those 12 projects
  and zero managed root Modules.

The retained agent-test checkout is deliberately not the clean proof: it still
contains the user-created `bureau_impossible_signals` project, captures, and
local vision configuration that exposed the bad seed. The staged index was
exported into a new repository and passed with zero `git status --short` lines,
12/12 portable projects, zero root Module files, and an exact 702-file workspace
manifest. Final acceptance still requires binding those results to the real
corrective commit.

## Asset status

The two external media inputs in the curated seed are recorded and cleared:

- `projects/streamdiff_workflows/assets/dancer_vert.mp4`
- `projects/touchdesigner_new_project/images/jellybeans.png`

Living Room SDF is fully procedural. Seven duplicated, unreferenced legacy
photo/video files were removed during release packaging.

## Blockers

Project portability, the zero-root-module contract, and the isolated staged-index
proof are clean. The remaining release task is to create the corrective content
commit and regenerate the workspace manifest against that exact commit.

The public remote still represents the previous release. No push, tag, or
release is authorized until the user explicitly approves G13 after reviewing
the complete clean-checkout candidate.

## Last devlog

`docs/devlogs/2026-07-30-phase-6n-public-seed-release-candidate.md` records the
original assembly and the corrective post-landing audit.
