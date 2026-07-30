---
type: phase
phase_number: "6"
title: "Public Workspace Curation And Release Refresh"
status: planned
approval: pending
summary: "Recurate the public project lineup, refresh approved projects from a clean private source, establish Interaction Lab UI and native-camera references as the default authoring foundations, and stop for operator review at every named creative gate before final publication."
---

# Phase 6 - Public Workspace Curation And Release Refresh

## Overview And Motivation

The public workspace is a curated product surface, not a mirror of the private authoring
workspace. Since the first official-example release, several projects have advanced in private,
the Interaction Lab UI system has become the preferred authored-interface foundation, the native
internal-camera contract has replaced project-local camera conventions, and four new projects are
candidates for publication. At the same time, five currently public projects should leave this
release.

This phase builds a new release candidate from an explicit allowlist. It starts from clean,
commit-addressed source snapshots; stages and proves one project at a time; promotes that project
into the public release candidate only after its human gate passes; and keeps the user's visual,
interaction, and curation judgment as a real gate. Automated checks may prepare evidence and
continue within an approved project slice, but they cannot approve a project's look, feel,
inclusion, or publication.

No push is part of this phase. The final public push is a separate hard-stop decision after the
user reviews the complete clean-clone release candidate.

## Relationship To Earlier Phases

Phase 6 supersedes Phase 1's public lineup and Phase 5's assumption that all earlier official
examples remain in the collection. It does not retroactively change their historical completion
records.

Phase 3's latest Interaction Lab implementation is the UI authority for this release, subject to
the operator gesture pass required here. The reusable `sui3_*` foundation, authoring template, and
documentation must agree before another project is approved.

Phase 6 replaces Phase 1's blanket topology assumptions with the role-specific readiness matrix
below. It retains Phase 1's portability, active-module, preset, documentation, no-nesting, and
clean-load bar wherever the project role supports them; replaces the old 6-10 control target with
the current 4-8 control doctrine; and replaces the old shared-camera default with the mandatory
native internal-camera contract. Phase 6 also adds one-project-at-a-time StreamDiff discipline, a
measured optimization gate for Face Collage, and explicit human approval after every named creative
review.

## Problem Statement

### Before

- The public repository contains Desert Totem, Fruit Atlas Scatter, Procedural Building System,
  StreamDiff Collage, and Topographic HUD even though they are not wanted in this release.
- Public copies of Industrial Lattice, Interaction Lab, Living Room SDF, Strata, Face Collage, and
  StreamDiff Workflows may lag their private counterparts.
- Cloth Lab, Autopsia, Scientific Organism, and StreamDiff Brush Canvas exist only in private.
- Autopsia's pads require a Y-direction audit before it can be considered publishable.
- Face Collage needs measured optimization and another visual review.
- Interaction Lab contains the preferred UI language, but the public workspace does not yet make
  it unmistakably the default import/template foundation.
- The focused internal-camera example is tied to Procedural Building System, which is leaving the
  public lineup.
- The private checkout is dirty, including changes under Autopsia, StreamDiff Brush Canvas, and
  StreamDiff Workflow 06, so it cannot safely serve as an unqualified "latest" source.
- Earlier automated completion states do not represent the user's new project-by-project curation
  decisions.

### After

- The public project table, promotion allowlist, filesystem, and documentation agree on one
  reviewed lineup.
- Every promoted file is traceable to a fetched private commit or to an explicitly accepted local
  overlay.
- Interaction Lab and the shared `sui3_*` kit are the obvious default starting point for authored
  UI.
- A compact camera reference independent of any excluded project visibly proves native Fly and
  Orbit operation and multipass alignment.
- Every included project loads, compiles, advances frames, responds visibly to its primary
  interactions, passes portability checks, and has current documentation.
- Face Collage has a measured performance improvement with no approved visual regression.
- Autopsia is included only if its pad direction and full hands-on review pass.
- StreamDiff Canvas replaces StreamDiff Collage, with its source and public name explicitly
  approved.
- The user reviews each named project after automated evidence is ready and before the next
  creative slice is treated as accepted.
- The final release candidate is proven from a clean public clone and remains unpushed until the
  user explicitly authorizes publication.

## Scope And Curation Ledger

### Include And Refresh

| Project | Public slug | Decision | Required human review |
| --- | --- | --- | --- |
| Interaction Lab | `interaction_lab` | Include; refresh first | UI appearance, panel behavior, every primary gesture |
| Industrial Lattice | `industrial_lattice` | Include | Final look, motion, camera feel, beginner clarity |
| Strata | `strata` | Include | Composition, controls, motion, final output |
| Face Collage | `face_collage` | Include after optimization | Visual parity/quality and performance tradeoff |
| Living Room SDF | `living_room_sdf` | Include | Scene quality, navigation, assets, graph clarity |
| StreamDiff Workflows | `streamdiff_workflows` | Include | Each workflow independently |
| Cloth Lab | `cloth_lab` | New inclusion | Cloth response, stability, audio/interaction feel |
| Scientific Organism | `scientific_organism` | New inclusion | Visual identity, motion, controls, performance |
| StreamDiff Canvas | name to approve | New inclusion replacing Collage | Painting behavior, reset/clear, output quality, name |

### Conditional

| Project | Default | Inclusion condition |
| --- | --- | --- |
| Autopsia | Hold outside public | Include only after the pad Y audit, hands-on interaction pass, visual review, portability proof, and explicit user approval |

### Exclude From This Release

| Project | Action |
| --- | --- |
| Desert Totem | Remove from the public tree, config, tables, and links; preserve in private and Git history |
| Fruit Atlas Scatter | Remove from the public tree, config, tables, and links; preserve in private and Git history |
| Procedural Building System | Extract the reusable camera reference, then remove the project from public |
| StreamDiff Collage | Remove after StreamDiff Canvas is accepted as its replacement |
| Topographic HUD | Default to exclude for this release; confirm at the curation gate because the original note was tentative |

## Governing Contracts And Traceability

| Contract | Requirement enforced by this phase | Proof/gate |
| --- | --- | --- |
| `AGENTS.md` live-discovery and health rules | Discover capabilities; compile and inspect real health/frames; never use diagnostic imagery | 6A, every project technical gate, 6N |
| `knowledge/ui-authoring.md` | Responsive `follow_panel` layout, matched drawn/hit rectangles, useful direct manipulation, no Properties duplication | 6C and every UI-bearing project |
| `knowledge/ui-interactions.md` | Real pointer/keyboard behavior, durable state, selection, and meaningful immediate response | 6C, 6L, 6M |
| `knowledge/internal-camera-template.md` | Native camera default, injected matrices, Fly saved default, real Fly/Orbit proof, no unjustified external rig | 6D and every 3D project |
| `knowledge/performance-proof.md` | Live health, rolling cook rate, before/after profiles, hotspot explanation | 6E-6M and 6N |
| `knowledge/streamdiff.md` | One workflow at a time, required packs documented, hold/one-shot behavior used appropriately | 6I and 6M |
| Phase 1 official-example readiness | Portable paths, active modules only, current README, meaningful controls/presets, clean public load | 6B, every project, 6N |
| Phase 3 Interaction Lab v2 | `sui3_*` behavior and the four-station interaction contract | 6C |

No criterion can pass on file existence, a successful compile, or a screenshot alone when the
deliverable is visible or interactive. Captures used for review must state what visible content and
change they prove.

## Current Public-Example Readiness Matrix

This matrix is the Phase 6 authority when Phase 1's old gallery-oriented topology conflicts with a
project's current role.

| Role | Projects | Scene/group/output contract | Preset/control contract | Proof/documentation contract |
| --- | --- | --- | --- | --- |
| Show-ready aesthetic look | Industrial Lattice, Face Collage, Scientific Organism, StreamDiff Canvas | One flat top-level Scene Group containing the complete active look and exactly one Group Output carrying the real final texture | 4-8 high-impact exposed controls; 3+ group presets including a healthy `Performance`; `Fidelity` for a heavy 3D look; 2+ useful project-scoped node presets | README with prerequisites, controls, presets, remix path; content-specific proof; clean-load and portability |
| Standalone modular aesthetic study | Strata, Living Room SDF | One flat top-level Scene Group; no Group Output required because the current standalone configs explicitly expect zero | 4-8 high-impact controls; 3+ group presets; 2+ useful node presets | Same README, proof, clean-load, and portability bar as a show-ready look |
| Authored tool/instrument | Interaction Lab, Cloth Lab, conditional Autopsia | Flat control-only groups where the saved project uses groups; no synthetic final Group Output | Curated controls only; Interaction Lab retains its station/group and stateful preset contract; Cloth Lab and Autopsia require a documented recoverable default plus 2+ useful node/project presets when the live identity supports them | Real gesture/state/output proof, README walkthrough, clean-load and portability |
| Technique specimen suite | StreamDiff Workflows | No Scene Group or Group Output required | No artificial preset bank; each workflow freezes and documents the exact proven engine/profile state | One independent README/proof record and clean-load result per workflow |
| Focused reference | Native-camera reference | No Scene Group, Group Output, or performance surface required | One useful saved Fly default; no exposed camera rows | Minimal readable graph, real Fly/Orbit and aligned auxiliary-output proof, direct authoring links |

No project may nest Scene Groups. An exemption removes only the named topology requirement; it does
not weaken health, visible behavior, active-module, path, asset, documentation, or human-review
criteria.

## Shared Promotion Lifecycle

For 6C-6M, "promotion" always means this ordered sequence:

1. Reconcile and edit the project in the dedicated Phase 6 release-source worktree.
2. Stage a disposable promotion target and run technical/visual proof there.
3. Present the project at its named human gate with `approval: pending`.
4. After explicit approval, apply promotion to the public release-candidate branch, validate it,
   and commit only that approved slice.
5. If the gate returns `revise` or `hold`, do not copy that candidate into the public branch.

This sequence overrides any later shorthand such as "promote, compile, review."

## Shared Performance Gate

Before changing any project, record its intended saved review state, resolution, a numeric complete-
graph cadence or frame-budget target, any heavy-node budget share, the settled sample window, and a
plain interaction-responsiveness test. Compare like-for-like states, change one expensive parameter
family at a time, and immediately revert unexplained cadence or responsiveness regressions.

Every project review record must contain the target, baseline samples, candidate samples, hotspot
explanation, and observed interaction response. CPU wall-time/cook-rate data must not be described
as GPU timing or VRAM attribution. A known hotspot may remain only when it is explained, inside the
predeclared release target, and accepted at the project's human gate.

## Shared Verification Record

Every project slice produces a review record with this conceptual schema:

```text
{
  project,
  source_commit,
  local_overlay_commit_or_diff,
  promoted_paths[],
  compile: {modules[], status},
  runtime: {healthy, health_reasons[], frames_before, frames_after, resolution, format},
  performance: {
    target: {resolution, complete_graph_budget, heavy_node_share, responsiveness_check},
    baseline_samples[], candidate_samples[], delta, hotspots[], interaction_response
  },
  interactions: [{gesture, expected_visible_change, observed}],
  captures: [{path, content_assertion}],
  portability: {absolute_paths[], forbidden_artifacts[], validator_passed},
  documentation: {requirements_current, controls_current, remix_path_current},
  human_gate: {gate_id, status, notes}
}
```

`human_gate.status` begins as `pending`. Automation never changes it to `approved`.

## Deliverables

| ID | Feature | Primary tools/actions | Status |
| --- | --- | --- | --- |
| D1 | Commit-addressed source ledger and three-way diff | Git fetch/clean worktree, hashes, report | Planned |
| D2 | Approved curation allowlist and exclusion report | promotion config, README census, dry-run | Planned |
| D3 | Canonical Interaction Lab UI foundation | `module-ui.ps1`, viewport proof, docs/templates | Planned |
| D4 | Standalone native-camera reference | Module HLSL/YAML, native viewport camera, captures | Planned |
| D5 | Refreshed existing projects | promotion rails, compile/health/profile/proof | Planned |
| D6 | Reviewed new project additions | project-specific runtime and interaction proof | Planned |
| D7 | Conditional Autopsia decision | pad audit, hands-on review, explicit inclusion decision | Planned |
| D8 | StreamDiff Canvas replacement | source reconciliation, interaction/engine proof, naming | Planned |
| D9 | Clean-clone public release candidate | full validator, cold load, link/asset/license scan | Planned |
| D10 | Human-reviewed release packet | evidence index, decisions, unresolved items, push hold | Planned |

## Sub-Phase 6A - Source Freeze And Reconciliation Ledger

This is release substrate only; nothing visible is promoted by 6A.

### Contract

| Field | Value |
| --- | --- |
| Parameters | Private remote, public remote, private dirty checkout, persistent Phase 6 release-source worktree/branch, candidate project list |
| Response schema | `{private_remote_commit, public_commit, dirty_paths[], per_project_diff[], local_overlays[], unresolved[]}` |
| UE APIs | N/A |
| Primary actions | Fetch both remotes; create a clean private source worktree/clone; compare public, private remote, and relevant local edits |

### Implementation Details

- Do not stash, reset, clean, or otherwise disturb the current private checkout.
- Fetch the private and public remotes and record full commit ids.
- Create a persistent sibling worktree on a dedicated `phase-6-public-refresh` branch rooted at the
  fetched private `origin/main`; bring this plan commit onto it without switching or cleaning the
  dirty main checkout. This branch, not an ephemeral clone, owns all accepted overlays, fixes, and
  per-project release commits.
- Compare each candidate directory against public.
- For Autopsia, StreamDiff Brush Canvas, and StreamDiff Workflow 06, also compare the current local
  uncommitted version. Record local changes as overlays, not as implicit source truth.
- Treat the current local StreamDiff Brush Canvas checkpoint as the default creative authority:
  `docs/devlogs/2026-07-29-streamdiff-laser-etch-checkpoint.md` explicitly says it is newer and must
  not be replaced by an older remote. G0 may reverse that default only through an explicit decision.
- If the other-PC work is absent from the fetched remote, stop and report exactly what is missing.

### Pass Criteria

1. The ledger names full source/public commits and every candidate project's source path.
2. The dirty private checkout has byte-identical status before and after the source setup.
3. Every local-only candidate change is visible in the ledger; none is silently discarded or
   silently promoted.
4. The release-source branch has a clean status after each accepted overlay is committed, and the
   dirty main checkout retains byte-identical status.
5. The user reviews the ledger and explicitly selects the source or overlay for every unresolved
   project before 6B applies public changes.

### Human Gate G0 - Source Authority

**Tier: hard stop.** Present one compact reconciliation table. Continue only after the user
confirms the unresolved source choices. Ordinary files that are identical or unambiguously newer
on fetched private `origin/main` do not require individual approval.

## Sub-Phase 6B - Curation Rails And Exclusion Staging

This is packaging substrate; it changes the proposed collection but does not approve any creative
project.

### Contract

| Field | Value |
| --- | --- |
| Parameters | Curation ledger, project allowlist, exclusion list, promotion config, public README |
| Response schema | Existing promotion report plus `{expected_projects[], actual_projects[], excluded[], stale_links[], exclusive_shared_paths[], destructive_operations[], minimum_version, capability_schema_hash}` |
| UE APIs | N/A |
| Primary actions | Update config in a staging worktree; report-only promotion; stage but do not apply exclusions before approval |

### Implementation Details

- Add the approved refresh/new candidates to `tools/official-examples.config.psd1`.
- Remove excluded projects from the proposed allowlist and documentation.
- Compute which shared modules are used only by excluded projects.
- Add an exact-set project census and an exclusion/dependency deletion planner. The current
  promotion script deletes stale files only inside selected replacement scopes; removing a project
  from the allowlist does not make its whole public directory appear in the report. The new planner
  must list each whole-project deletion, resolve it under the public root, prove it is tracked and
  recoverable, and refuse apply before G1.
- Inventory the highest Sentinel feature/version requirement across every candidate manifest and
  project. Update the config and public requirements to that maximum rather than retaining the
  current unproven `0.5.35` floor. Record the live proof host version and capability schema hash;
  the host version is evidence, not automatically the minimum.
- Run `tools/promote-public.ps1` without `-Apply` and retain the complete operations report.
- Capture JSON stdout or write reports to an absolute evidence path outside both Git worktrees.
  Relative `-ReportPath` values write under `SourceRoot` and would invalidate the unchanged-tree
  criterion.
- Treat Topographic HUD as excluded by default but call it out separately.
- Do not remove StreamDiff Collage until StreamDiff Canvas passes 6M.

### Pass Criteria

1. Config, proposed project table, exact-set project census, and filesystem operation report
   describe the same lineup.
2. Every whole-project and exclusive-dependency deletion is explicitly reported, contained within
   the public checkout, tracked, and recoverable from Git.
3. No shared module still referenced by an included project appears in the deletion set.
4. The report-only promotion changes neither source nor public worktree.
5. The declared minimum Sentinel version equals the highest verified candidate requirement, and the
   report records the live host version plus capability hash used for proof.
6. The user explicitly approves the lineup and staged removal list before exclusions are applied.

### Human Gate G1 - Release Lineup

**Tier: hard stop.** The review packet highlights Topographic HUD, the timing of StreamDiff Collage
removal, and any shared dependency deletion. No removal is applied before approval.

## Sub-Phase 6C - Interaction Lab And Canonical UI Foundation

### Contract

| Field | Value |
| --- | --- |
| Parameters | Latest Interaction Lab, `sui3_*` headers, UI template, scaffold tool, four station extents and gestures |
| Response schema | UI validation, normalized hashes, panel extents, gesture outcomes, data-port/state readback, visual assertions |
| UE APIs | N/A; use Sentinel Module UI/runtime surfaces |
| Primary actions | Reconcile/stage lab; establish canonical shared location; update scaffold/docs; run hands-on station proof; promote only after G2 |

### Implementation Details

- Make root `modules/_shared/ui/sui3_*` the canonical reusable implementation.
- Document direct import as the default and project-local vendoring as an intentional portability
  option, with an explicit sync/version rule to prevent drift.
- Make `tools/module-ui.ps1` scaffolding start from the canonical current foundation.
- Link Interaction Lab prominently from root Quick Start, UI knowledge, and UI authoring skills.
- Scan every authoring entry point (templates, skills, knowledge, README, and active examples).
  Canonical instructions must use `sui3_*`; remaining `sui_*`/`sui_v2` references must be removed
  or explicitly labeled historical/compatibility material.
- Validate Style Authority, Motion Console, Spline Desk, and Gizmo Desk at 640x360, 1600x900,
  1920x403, and the live dock extent.
- Exercise real pointer/keyboard gestures inside Module previews; synthetic parameter writes do not
  substitute for these.

### Pass Criteria

1. All shared/template copies have the intended normalized hashes and generated UI headers validate.
2. Captures at every required extent visibly retain the Phase 3 language: crisp 1px
   hairlines/graticules/brackets, attached live readouts, hover-inert chrome, semantic amber only for
   established selection/live state, and no clipped or overlapping captions.
3. Style Authority visibly governs at least one other station: changing a published theme value
   changes the specimen, its attached readout, its control output, and the downstream station.
4. Motion Console publishes live, nonconstant outputs; its pad agrees with the host Properties value
   and reticle; Burst visibly rises and returns to baseline rather than latching.
5. A human can use Spline Desk select, sustained anchor/handle drag, marquee, tangent mode, delete,
   close, cancel, and immediate undo. Geometry tracks the pointer without lag or acceleration,
   `Spline_Output` visibly changes, and undo restores the pre-drag output.
6. A human can use Gizmo Desk single/multi-selection, translate, rotate, nonuniform/uniform scale,
   world/local mode, commit, cancel, and immediate undo on lit geometry. The selected objects and
   shared pivot behave visibly as documented.
7. Save/reload and stateful preset recall restore visibly different spline/gizmo state, not merely
   parameter readback.
8. Controls remain legible and their drawn rectangles align with host hit rectangles at every
   required extent.
9. In every plausible active-panel/focus state the whole lab remains healthy and meets the inherited
   Phase 3 floor of at least 55 cooks/s on the reference proof host, or G2 explicitly approves a
   newly measured replacement budget before promotion.
10. A newly scaffolded throwaway UI Module imports the canonical foundation, compiles, and responds
    to a real control gesture at two panel extents; both bound state and drawn output change.
11. The workspace-wide entry-point scan finds no unlabeled active authoring instruction that still
    teaches v1/v2 as the default.
12. The user approves the UI feel and the claim that this is the default foundation.

### Human Gate G2 - UI Authority

**Tier: hard stop.** Hold one hands-on review after all automated extent/hash/data checks pass.
Record requested adjustments and repeat this gate after material UI changes.

## Sub-Phase 6D - Accessible Native-Camera Reference

### Contract

| Field | Value |
| --- | --- |
| Parameters | Neutral reference renderer, color/depth or equivalent camera-dependent outputs, native Fly/Orbit state |
| Response schema | Compile/health, manifest camera declarations, camera state, paired viewpoint captures, alignment assertions |
| UE APIs | N/A; use injected Module camera matrices and native viewport camera |
| Primary actions | Extract the reusable lesson from Procedural Building System; build a standalone reference; link it from authoring entry points |

### Implementation Details

- The reference must not depend on the excluded Procedural Building System project.
- Publish it at `projects/camera_reference/camera_reference.sentinel` with a bundled reference
  renderer and README. A standalone project is chosen over a loose `examples/` fragment because the
  user must be able to open it and immediately operate the real native viewport camera.
- Use `features: [camera]`, `viewport.interactions: [camera]`, empty `camera_ref`, injected matrices,
  and `_CameraPos` in every camera-dependent pass.
- Save Fly as the default. Document and visibly demonstrate host-owned Orbit without adding a
  shader-local camera equation.
- Include an output pair that makes camera alignment falsifiable, such as color and depth.
- Put the example on a short path from root README, `knowledge/internal-camera-template.md`, and
  3D authoring skills.

### Pass Criteria

1. Static inspection positively proves `features: [camera]`,
   `viewport.interactions: [camera]`, empty `camera_ref`, `_CameraPos`, DirectX-Y-flipped
   `_InvViewProjMatrix` ray construction (or `_RayDirection` where verified equivalent), and
   `_ViewProjMatrix` use for draw geometry. It also finds no parallel ray equation, hard-coded
   orbit, or unjustified camera node.
2. Every camera-dependent color, depth, normal, pick, or overlay pass in the example consumes the
   same injected state, and no camera ownership/binding/mode/FOV/pose row is promoted onto a Scene
   Group or authored performance surface.
3. A human can use Fly navigation and visibly move through the reference scene.
4. A human can switch to Orbit and visibly orbit the same geometry around the intended target.
5. Paired captures from materially different viewpoints show color plus a real camera-aligned
   auxiliary output (depth at minimum; normals/picking too if exposed) remaining spatially aligned.
6. Reload restores a useful pose with Fly as the default.
7. The user approves the example as the obvious camera starting point.

### Human Gate G3 - Camera Feel And Discoverability

**Tier: hard stop.** Review real Fly and Orbit operation, not parameter readback. Do not remove the
old Procedural Building System public project until this reference is accepted.

## Sub-Phase 6E - Industrial Lattice Refresh

### Contract

| Field | Value |
| --- | --- |
| Parameters | Approved private source, lattice renderer/post modules, native camera, controls/presets |
| Response schema | Shared verification record |
| UE APIs | N/A |
| Primary actions | Stage, compile, inspect, profile, exercise camera/controls, refresh README; promote only after G4 |

### Implementation Details

- Reconcile the saved graph and its shared `steel_lattice`/post dependencies from the approved
  source rather than copying the whole private module tree.
- Keep the compact graph readable and preserve only controls and presets with obvious visual value.
- Compare camera behavior and rolling profile against the approved private source before promotion.

### Pass Criteria

1. The complete project loads healthy with advancing frames and all active modules compiled.
2. Fly and Orbit visibly change the viewpoint using the approved camera contract.
3. Its important controls/presets visibly change the lattice form or treatment without blank,
   generic, or misleading intermediate previews.
4. A short recording contains the intended nonzero temporal change in lattice/lighting/post state;
   a static repeated frame cannot satisfy the motion review.
5. The shared performance target passes with no unexplained regression against the private baseline.
6. The role-specific Scene Group, Group Output, control, and preset requirements pass.
7. A clean-path promotion passes portability validation.
8. The user approves the final look, motion, camera feel, and beginner-facing clarity.

### Human Gate G4 - Industrial Lattice

**Tier: hard stop.** Present the running project and evidence only after technical checks pass.

## Sub-Phase 6F - Strata Refresh And Final Review

### Contract

| Field | Value |
| --- | --- |
| Parameters | Approved private source, active composition lanes, controls/presets, final output |
| Response schema | Shared verification record |
| UE APIs | N/A |
| Primary actions | Stage, remove stale iterations, compile, profile, exercise composition controls, refresh docs; promote only after G5 |

### Implementation Details

- Inventory active saved-graph module paths first, then remove only unreferenced bundled iterations.
- Inspect each generator/data/composite/post lane at its own preview before judging the final output.
- Freeze one review preset and motion interval so before/after captures and profiles are comparable.

### Pass Criteria

1. Every active lane has a meaningful preview and contributes visibly to the final composition.
2. Primary controls and at least three intended presets produce visibly distinct, healthy looks.
3. Dead nodes, inactive iteration modules, and stale UI copies are absent from the promoted bundle.
4. A short recording shows the intended nonzero evolution in at least two active lanes while the
   final composite remains coherent; repeated static frames cannot satisfy this criterion.
5. The saved Draft renderer preserves its approved 480x720 live state and approximately 60 Hz
   renderer path. The known Features hotspot is remeasured with its 320x480 analysis proxy and must
   remain explained and inside the predeclared whole-graph responsiveness target.
6. The role-specific Scene Group, control, and preset requirements pass.
7. Portability and documentation checks pass.
8. The user approves composition, motion, controls, and final output.

### Human Gate G5 - Strata

**Tier: hard stop.** The user reviews Strata once more as a complete instrument.

## Sub-Phase 6G - Face Collage Optimization And Review

### Contract

| Field | Value |
| --- | --- |
| Parameters | Approved source, meaningful face/live source, fixed review preset, 720p-class resolution, profile samples |
| Response schema | Shared verification record plus `{baseline_samples[], candidate_samples[], visual_diff, accepted_tradeoff}` |
| UE APIs | N/A |
| Primary actions | Establish baseline; identify hotspot; optimize one cause at a time; compare motion/output; promote only after G6 |

### Implementation Details

- Use the same source, preset, resolution, warm-up, and profile window for baseline and candidate.
- Change one measured hotspot at a time and revert changes that do not improve rolling cadence.
- Do not lower creative quality merely to claim an optimization.
- Preserve real tracking/data behavior; diagnostic imagery is prohibited.

### Pass Criteria

1. Baseline and candidate are reproducible and identify the actual limiting node(s).
2. The accepted candidate shows a material, repeatable cadence or wall-time improvement; the
   threshold is recorded from the measured baseline before tuning, not invented afterward.
3. Side-by-side still and motion review show no unapproved loss of subject legibility, collage
   density, temporal character, or intended post treatment.
4. All key controls/presets still visibly operate and the graph remains healthy.
5. The show-ready aesthetic Scene Group, Group Output, control, and preset requirements pass.
6. Promotion and portability validation pass.
7. The user explicitly accepts the performance/quality tradeoff and final look.

### Human Gate G6 - Face Collage

**Tier: hard stop.** Present baseline/candidate evidence together. Automation cannot decide that a
visual tradeoff is acceptable.

## Sub-Phase 6H - Living Room SDF Refresh

### Contract

| Field | Value |
| --- | --- |
| Parameters | Approved source, active modules/assets, native camera, editor/controls/presets |
| Response schema | Shared verification record plus asset/dependency inventory |
| UE APIs | N/A |
| Primary actions | Reconcile active graph, remove obsolete iterations, validate assets, camera, editor, presets, docs |

### Implementation Details

- Resolve active module variants from the saved graph instead of assuming the highest numbered
  directory is current.
- Produce an asset inventory with source, purpose, size, and redistribution status before promotion.
- Test editor state, final renderer, and all camera-dependent auxiliary outputs from the same saved
  project state.

### Pass Criteria

1. Only active module variants and necessary redistributable assets ship.
2. The renderer and all camera-dependent passes follow the approved native-camera contract unless a
   separately justified shared-camera exception is documented.
3. A human can navigate, select/manipulate intended scene elements, and see the final room update
   immediately; undo/cancel work where promised.
4. Named presets create visibly distinct, healthy room states.
5. The standalone modular-study Scene Group, control, and preset requirements pass.
6. Clean-path load, profile, asset/license, and portability checks pass.
7. The user approves scene quality, navigation, interaction, graph clarity, and bundled assets.

### Human Gate G7 - Living Room SDF

**Tier: hard stop.** Any proposal to remove or replace a visible asset is included in this review.

## Sub-Phase 6I - StreamDiff Workflows Reconciliation

### Contract

| Field | Value |
| --- | --- |
| Parameters | Public/private/local three-way sources, six workflows, required engine packs |
| Response schema | One shared verification record per workflow plus source-resolution ledger |
| UE APIs | N/A |
| Primary actions | Resolve versions; open one workflow at a time; validate health, behavior, hold/one-shot use, docs |

### Implementation Details

- Do not assume one repository wins every file. Preserve a public-only improvement if it remains
  correct, and explicitly accept or reject the local Workflow 06 overlay.
- Open and prove only one StreamDiff workflow at a time to avoid engine-memory spikes. Use a fresh
  Sentinel process between incompatible profile/resolution slices, with relaunch performed by the
  operator or a verified interactive `/IT` task.
- Give every saved workflow its own prerequisites, expected behavior, and failure diagnosis.
- Execute as six independently commit-addressed slices so a failure or hold cannot block evidence
  collection for the others:

| Slice | Workflow | Falsifiable executing assertion |
| --- | --- | --- |
| 6I.1 | `01_2d_feedback_zoom` | With a frozen prompt/seed, a recorded nonzero zoom visibly rescales prior-frame content over time; the zero-zoom control does not |
| 6I.2 | `02_depth_parallax_zoom` | Depth-enabled motion produces visibly different near/far displacement correlated with the captured depth map; the flat-depth control does not |
| 6I.3 | `03_backrooms_flythrough` | A recording shows sustained architecture-relative parallax/flythrough rather than a uniform 2D scale |
| 6I.4 | `04_direct_variant_mux` | Selecting each Mux input visibly changes the output, while nonselected variants enter hold and stop increasing render counts |
| 6I.5 | `05_video_depth_control` | Meaningful video changes produce corresponding depth structure and a visibly related generated composition |
| 6I.6 | `06_procedural_warp_map` | The raw meaningful authored flow-map direction is captured and the final displacement moves in the corresponding direction; the same creative source with `warp_enabled=false` removes that displacement without introducing diagnostic imagery |

### Pass Criteria

1. The source ledger explains the chosen version of every workflow.
2. Each workflow independently reaches healthy frame progression with its required packs installed.
3. Each slice satisfies its tabled falsifiable executing assertion with the named control case and
   content-specific still/motion evidence.
4. Non-selected variants do not consume avoidable diffusion work where hold/solo behavior applies.
5. A clean checkout resolves every project/module/media path.
6. Every slice has an independent source, proof, and clean-load record; no six-workflow mega-step
   can be marked complete on aggregate health alone.
7. The user reviews and approves each workflow; a failure holds only that workflow and does not
   silently lower the bar for the set.

### Human Gate G8 - StreamDiff Workflows

**Tier: hard stop.** Run as one review session, but record an individual approve/hold decision for
each workflow.

## Sub-Phase 6J - Cloth Lab Candidate

### Contract

| Field | Value |
| --- | --- |
| Parameters | Approved source, cloth presets, interactions/audio inputs, restart and soak duration |
| Response schema | Shared verification record plus stability/constraint diagnostics |
| UE APIs | N/A |
| Primary actions | Stage, compile, exercise cloth, test reset/reload, profile/soak, document prerequisites; promote only after G9 |

### Implementation Details

- Start from the committed cloth baseline and record any accepted local overlay separately.
- Exercise impulses and parameter extremes one at a time, restoring the baseline immediately after
  instability.
- Use the canonical Audio Bands outputs if audio reactivity is part of the saved project; do not
  revive superseded `pulse2_*` or `cryo_pulse` paths.

### Pass Criteria

1. The cloth remains stable through the documented interaction/audio range and a representative
   soak; no NaNs, explosive constraints, or unrecoverable state occur.
2. Primary interaction/audio events visibly and immediately affect the cloth as documented.
3. Reset, save/reload, and the intended default state behave predictably.
4. The authored-instrument default/preset requirements pass without adding a synthetic Group Output.
5. Profile and portability checks pass with current cloth/audio documentation.
6. The user approves material response, motion, controls, and default presentation.

### Human Gate G9 - Cloth Lab

**Tier: hard stop.** This is a physical/taste review of cloth response, not a health-only check.

## Sub-Phase 6K - Scientific Organism Candidate

### Contract

| Field | Value |
| --- | --- |
| Parameters | Approved source, generator/data lanes, renderer, controls/presets, motion interval |
| Response schema | Shared verification record |
| UE APIs | N/A |
| Primary actions | Stage; inspect graph/data contracts; compile, profile, record motion, exercise controls, document; promote only after G10 |

### Implementation Details

- Walk the graph in semantic order from authored generator through data lanes, renderer, and finish.
- Capture schemas/counts for structured ports and verify each preview represents its own
  intermediate state.
- Freeze a representative preset and recording interval for the human motion review.

### Pass Criteria

1. Every intermediate generator/data lane has an inspectable, meaningful preview and valid schema.
2. Controls/presets visibly alter organism structure, motion, or treatment as documented.
3. A motion recording shows coherent evolution without blank, stuck, or discontinuous behavior.
4. The show-ready aesthetic Scene Group, Group Output, control, and preset requirements pass.
5. Camera use, performance, portability, and documentation pass their governing contracts.
6. The user approves the visual identity, motion language, interaction value, and default look.

### Human Gate G10 - Scientific Organism

**Tier: hard stop.** The project is not included solely because its technical graph is healthy.

## Sub-Phase 6L - Autopsia Pad Fix And Conditional Decision

### Contract

| Field | Value |
| --- | --- |
| Parameters | Approved source/overlay, every XY pad, host Properties coordinate contract, primary gestures, inclusion flag |
| Response schema | Shared verification record plus `{pad, pointer_points[], properties_values[], reticle_points[], published_values[], consumer_effects[]}` |
| UE APIs | N/A |
| Primary actions | Audit coordinate paths; fix exactly-once Y conversion; exercise asymmetric points and gestures; review inclusion |

### Implementation Details

- Test asymmetric points on both sides of `0.5` in both axes; symmetric center tests cannot detect
  inversion.
- Use the host Properties XY value as the independent authority. Track pointer position, Properties
  value, drawn reticle, durable state/control output, and the effect-producing consumer. Prior
  Interaction Lab work proved that counting conversions is unfalsifiable: four internal surfaces
  can agree while all remain upside down against the host.
- Count/conversion inspection is diagnostic only. The pass condition is observable agreement with
  the host contract and the intended semantic direction.
- Re-run all Autopsia primary gestures after any coordinate fix.

### Pass Criteria

1. For every pad, asymmetric top/bottom and left/right gestures make the host Properties value,
   drawn reticle, published/durable value, and actual effect-producing consumer agree on the
   documented semantic direction.
2. The comparison is proven at two asymmetric points on each side of `0.5` per axis; center-only or
   internally self-consistent evidence cannot pass.
3. Selection, drag, clear/reset, and other primary gestures visibly work through real viewport
   input.
4. If proposed for inclusion, the authored-instrument default/preset requirements pass without
   adding a synthetic Group Output.
5. The project loads healthy, meets its predeclared performance target, and passes
   portability/documentation checks.
6. The user performs the pad review and makes an explicit `include` or `hold` decision.

### Human Gate G11 - Autopsia Inclusion

**Tier: hard stop.** This is both a hands-on pad-direction review and an irreversible lineup
decision for this release. Default is `hold` if approval is absent.

## Sub-Phase 6M - StreamDiff Canvas Replacement

### Contract

| Field | Value |
| --- | --- |
| Parameters | Remote/local source choice, public slug/title, brush/pad interactions, clear/reset, engine packs, memory behavior |
| Response schema | Shared verification record plus source/name decisions and memory/hold observations |
| UE APIs | N/A |
| Primary actions | Reconcile source; settle name; stage; compile; exercise painting; validate StreamDiff lifecycle; promote only after G12; then remove Collage |

### Implementation Details

- Resolve the other-PC remote version and current local overlay before changing the public slug.
- Close the current in-progress local laser-etch checkpoint first: settle or explicitly defer its
  documented smoke/trail tuning and commit the accepted local authority on the release branch before
  public packaging.
- Trace pointer coordinates through the editor state into the effect-producing pass, including any
  scaled texture passes; test both sides of `0.5` on each axis.
- Exercise StreamDiff hold/one-shot behavior and capture memory/health before and after clear/reset.
- Exclude the authored `Laser_Calibration_Grid` diagnostic generator from the public creative
  project and its proof. Preserve it in private or move it to a separately documented technical
  calibration tool; diagnostic imagery may not appear in creative construction or proof.
- Run three independently reviewable stages:

| Stage | Outcome |
| --- | --- |
| 6M.1 | Local authoritative checkpoint closed and committed; remote/local source reconciliation complete |
| 6M.2 | Public name, active modules, diagnostic-tool exclusion, and promotion diff prepared |
| 6M.3 | Raw producer, final canvas, StreamDiff lifecycle, motion, and VRAM observation proven for G12 |

### Pass Criteria

1. The chosen source includes all explicitly accepted other-PC and local work, with no silent merge.
2. At asymmetric points in all four canvas quadrants, a real paint/manipulation gesture visibly
   changes the raw effect-producing field/pass at the correct location and then the corresponding
   final generated output. A correct downstream marker cannot hide a misaligned producer.
3. Clear/reset returns to the documented state, and save/reload preserves only the intended state.
4. With meaningful creative content, hold freezes the generated image while the node stays healthy;
   `render_one` produces exactly the requested `render_count` output changes and then automatically
   returns to hold. Readback without captured output change cannot pass.
5. Record `sentinel_app diagnostic` total/used/free VRAM and shared-engine-pool state at idle,
   loaded, held, cleared, and reloaded checkpoints. Report deltas as observational whole-app data,
   not per-node GPU-memory attribution; graph profile remains CPU wall-time evidence only.
6. Required engine packs, lifecycle behavior, and failure diagnosis are current, and neither the
   active graph nor review evidence contains the Laser Calibration Grid or other diagnostic imagery.
7. The show-ready aesthetic Scene Group, Group Output, control, and preset requirements pass.
8. The public slug/title is explicitly approved and all links use it consistently.
9. Only after this project is approved is StreamDiff Collage removed from the release candidate.

### Human Gate G12 - StreamDiff Canvas

**Tier: hard stop.** Review painting feel, output quality, reset behavior, and the public name.

## Sub-Phase 6N - Clean-Clone Release Candidate And Publication Packet

### Contract

| Field | Value |
| --- | --- |
| Parameters | Approved project set, public release-candidate commit, clean clone, validation config |
| Response schema | Aggregate project records, validator result, stale-link scan, asset/license report, clean-clone smoke results, proposed diff |
| UE APIs | N/A |
| Primary actions | Assemble only approved slices; validate; cold-load each project; produce evidence index; hold push |

### Implementation Details

- Assemble the public tree only from project slices whose human gate is approved.
- Remove excluded content and stale references after replacement dependencies are accepted.
- Run the existing official-example validator, then run separate release-audit checks it does not
  currently provide:
  - exact equality between configured and actual `projects/` directories, with explicit
    review-only/internal exclusions;
  - tracked-file secret scan covering forbidden config names, provider/key-like assignments, and
    known key prefixes;
  - Markdown relative-link existence scan from every shipped README/knowledge/skill entry point;
  - tracked-file size report with review required above 50 MiB and a hard stop at 100 MiB unless an
    explicit distribution mechanism and allowlist are approved;
  - asset/license ledger recording source, purpose, redistribution status, and unresolved rights;
  - declared minimum Sentinel version/capability requirement versus the host actually used.
- Clone the exact release-candidate commit, not a mutable working tree, to a new clean path and
  cold-load every included project. Capture `unresolved_project_dirs[]` on every load. Sentinel has
  no restart-app IPC action, so required fresh-process isolation is an operator action or a verified
  interactive `/IT` scheduled task with SessionId checked; never relaunch from Session 0.
- Produce a compact release packet with one representative output and the approval record for each
  included project.
- Execute as three separately checkable integration stages:

| Stage | Outcome |
| --- | --- |
| 6N.1 | Approved slices assembled; exact-set, path, secret, link, size, license, and version audits green |
| 6N.2 | Exact commit cloned; every project cold-loaded with fresh content-specific output and unresolved-path report |
| 6N.3 | Evidence packet bound to the commit; aggregate human review ready for G13 |

### Pass Criteria

1. Public config, README, actual project-directory census, and release packet contain the same
   approved set; no excluded directory survives accidentally.
2. Every included project cold-loads from the clean clone, compiles, remains healthy, and advances
   frames.
3. Existing validator output plus the separate release-audit reports have no absolute paths,
   secrets, forbidden artifacts, missing active modules, stale links, unapproved large files,
   version mismatch, or unresolved asset/license questions.
4. Every representative artifact is regenerated from the exact clean-clone release commit and
   carries the commit plus relevant file hashes. Each project's critical interaction is replayed in
   the clone, or byte identity to the already approved slice is proven and the fresh final output
   satisfies the same content assertion.
5. The packet contains the fresh visual/interaction/performance evidence and corresponding
   human-gate result for every included project.
6. `git diff` contains only intentional release changes and all commits are independently
   reviewable.
7. The user reviews the complete release candidate and explicitly authorizes or declines the
   public push.

### Human Gate G13 - Final Release

**Tier: hard stop.** No push, tag, release, or external publication occurs without a new explicit
authorization after this review. Approval of earlier project gates is not push authorization.

## Autonomy And Human-In-The-Loop

### Operating Principle

Each sub-phase has an autonomous preparation interval followed by a deliberately placed human
review gate. The agent should batch compilation, runtime inspection, captures, profiling,
portability checks, documentation checks, and safe fixes so the user sees a concise review packet
rather than raw diagnostic churn. The agent must not advance a project's approval state or promote
it as accepted merely because those automated checks pass.

### Human-Intervention Points

| Gate | Review | Required decision |
| --- | --- | --- |
| G0 | Source reconciliation | Select any unresolved remote/local overlay |
| G1 | Curation/removal report | Approve lineup and recoverable public deletions |
| G2 | Interaction Lab | Approve canonical UI behavior and feel |
| G3 | Camera reference | Approve Fly/Orbit feel and discoverability |
| G4 | Industrial Lattice | Approve project |
| G5 | Strata | Approve project |
| G6 | Face Collage | Approve optimization tradeoff and project |
| G7 | Living Room SDF | Approve project and bundled assets |
| G8 | StreamDiff Workflows | Approve/hold each workflow |
| G9 | Cloth Lab | Approve project |
| G10 | Scientific Organism | Approve project |
| G11 | Autopsia | Include or hold |
| G12 | StreamDiff Canvas | Approve project, name, and Collage replacement |
| G13 | Complete release candidate | Authorize or decline push |

The order keeps foundation reviews first and runs StreamDiff Workflows as a fresh-process sequence;
StreamDiff Canvas remains late because it replaces an existing public project. If the user prefers
a single longer review session, evidence may be batched, but every gate still receives its own
recorded decision.

### Gate Tiers

#### Tier 1 - Self-Serve

The agent performs the check, records evidence, leaves `approval: pending`, and continues within
the current approved slice:

- Fetch, hash, diff, compile-check, compile polling, health/frame inspection.
- Profile collection, portability validation, stale-link scan, documentation consistency.
- Capture generation with explicit content assertions.
- Safe fixes that restore the already documented behavior without changing visual identity,
  interaction semantics, project lineup, or published dependencies.
- Report-only promotion runs and disposable clean-worktree validation.

Tier 1 never approves a creative project.

#### Tier 2 - Conditional Proceed

The following are pre-authorized only when their testable condition holds:

- Reconcile to fetched private `origin/main` when the public project has no unique newer change and
  no relevant local overlay exists.
- Apply a technical fix inside the active project when before/after proof shows the documented
  behavior is restored and there is no visual-identity change.
- Continue Face Collage optimization experiments while each experiment is individually revertible;
  revert any candidate that does not improve the frozen baseline or visibly harms the output.
- Install or use an already documented engine pack when the live GPU architecture and pack id
  match; license activation remains manual.
- Exclude Autopsia when G11 receives no approval; absence of approval never means include.
- Keep Topographic HUD excluded at G1 unless the user explicitly reverses the default.

#### Tier 3 - Hard Stop

- Every G0-G13 human review gate.
- Any source divergence or local overlay that changes which creative version would ship.
- Any destructive operation outside the exact public project paths approved at G1.
- Any change to core Sentinel/MCP/plugin source or to a governing product contract.
- Any missing or unclear asset redistribution right.
- Any change that materially alters a project's visual identity, primary interaction, camera
  ownership, resolution, or public name beyond what this plan specifies.
- Any requested Git history rewrite, force push, branch switch with uncommitted work, tag, release,
  or public push.
- A gesture-dependent criterion that cannot be exercised. It remains unproven and cannot be
  self-approved.

### Pre-Authorizations

- Create the dedicated persistent Phase 6 release-source branch/worktree from fetched private
  `origin/main`; leave the dirty private checkout untouched.
- Use disposable promotion targets for pre-gate proof, then apply and commit only an approved slice
  to the public release-candidate branch.
- Make reversible commits per foundation/project slice.
- Run live read-only discovery and install documented engine packs when required and architecture
  matched.
- Create temporary proof outside the promoted public file set.
- Fix compile, stale generated-header, relative-path, and documentation errors inside the active
  slice when the intended behavior is unambiguous.
- Remove StreamDiff Collage only after G12 approval.
- Preserve every excluded project in private and in public Git history.

### Hard Blockers

- The expected other-PC commit is absent and no approved local source contains it.
- Sentinel cannot run in the active interactive desktop for required visual/gesture proof.
- Required engine or meaningful source cannot be made available.
- A project depends on an asset that cannot legally ship.
- The user rejects a gate and the requested correction is not yet understood.
- Public/private histories diverge in a way that requires branch switching, rewriting, or conflict
  resolution without approval.

## Files Summary

### New

- `docs/phases/phase-6-public-workspace-curation-refresh.md`
- `projects/camera_reference/` as the standalone native-camera reference selected during audit.
- Per-project review records/evidence index, stored outside the promoted set unless intentionally
  curated for documentation.

### Modified During Planning

- `docs/implementation-plan.md`
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md` to preserve the workspace's identical entry-manual contract.

### Expected During Implementation

- `tools/official-examples.config.psd1`
- `tools/promote-public.ps1` and/or `tools/validate-official-examples.ps1` only if required for the
  new allowlist or stronger validation.
- Root `README.md`, relevant knowledge docs, UI templates/skills, camera docs.
- Approved project directories and their active dependencies.

### Explicit No-Change

- Sentinel application, MCP server, plugin, CUDA, TensorRT, and installer source.
- Dirty private authoring work unrelated to an explicitly accepted overlay.
- Private copies of excluded public projects.
- Public remote state until the final separately authorized push.

## Implementation Order

1. 6A source freeze and G0.
2. 6B curation report and G1.
3. 6C Interaction Lab/UI authority and G2.
4. 6D camera reference and G3.
5. 6E Industrial Lattice and G4.
6. 6F Strata and G5.
7. 6G Face Collage and G6.
8. 6H Living Room SDF and G7.
9. 6I StreamDiff Workflows and G8.
10. 6J Cloth Lab and G9.
11. 6K Scientific Organism and G10.
12. 6L Autopsia and G11.
13. 6M StreamDiff Canvas and G12.
14. 6N clean-clone release candidate and G13.

### Bounded Work Slices

The following seams keep the larger sub-phases independently verifiable in roughly one to two
sittings per slice:

| Sub-phase | Slice 1 | Slice 2 | Slice 3+ |
| --- | --- | --- | --- |
| 6C | Canonical header/template/entry-point census | Four-station static/automated regression | Hands-on gesture/performance pass and G2 |
| 6G | Frozen baseline, target, and ranked hotspot | Individually revertible optimization candidates | Motion/visual comparison and G6 |
| 6H | Active-module and asset/license inventory | Camera/editor/preset/runtime proof | Packaging review and G7 |
| 6I | One independently committed workflow per 6I.1-6I.6 slice | Fresh-process proof per slice | Batched individual decisions at G8 |
| 6M | 6M.1 local checkpoint closure | 6M.2 packaging/name diff | 6M.3 runtime/lifecycle/VRAM proof and G12 |
| 6N | 6N.1 assembly/static release audits | 6N.2 exact-commit cold loads | 6N.3 commit-bound packet and G13 |

Do not begin the next slice when the current slice's technical pass criteria are red. A human gate
occurs after its named slice set is technically ready; a held project does not block independent
later candidates unless they share the rejected dependency.

Within every live creative graph review, follow the workspace's visible one-node-at-a-time cycle
for any authored fixes or additions. Read-only health discovery may be batched, but node creation
and visible graph mutation may not.

## Verification Plan

1. Record exact source/public commits and current dirty status.
2. Run report-only promotion and inspect all operations.
3. For each Module, run compile-check before creation/reload and wait for async compile status.
4. Inspect live `info` for health, reasons, frames, preview, resolution, and format.
5. Use graph profile rolling cook rate for performance comparisons.
6. Focus and open important nodes; exercise controls through real interaction where promised.
7. Capture still or motion evidence with a written visible-content assertion.
8. Run `tools/module-ui.ps1 validate` for UI projects.
9. Run official-example validation and asset/path/link scans.
10. Present the project review packet and record the human gate.
11. Promote only approved slices into the public release candidate.
12. Repeat the complete validation from a clean public clone.

## Example Agent Workflow

```text
Read Phase 6 and the current gate state.
Confirm the private/public commits and dirty-worktree preservation.
Select only the next approved sub-phase.
Run live capability discovery.
Prepare the project autonomously:
  reconcile source
  compile and inspect health
  exercise automated/readback paths
  profile
  capture content-specific proof
  validate portability and docs
Apply safe fixes within the documented behavior.
Build a compact review packet.
Stop at the named human gate.
Record approve/hold/revise without inferring approval.
Commit the approved slice with approval metadata.
Continue only to the next authorized sub-phase.
At G13, stop before any push.
```

## Dependencies

1. Network access to both private and public remotes.
2. A persistent clean Phase 6 release-source branch/worktree plus the untouched dirty private
   checkout for overlay comparison.
3. Sibling `sentinel-workspace-public` checkout.
4. Sentinel running in the active interactive Windows desktop.
5. Live MCP capabilities for pipeline, graph, capture, viewport, preset, StreamDiff, audio, and
   state proof as used by each project.
6. Required GPU engine packs and meaningful project/live sources.
7. `tools/promote-public.ps1`, `tools/validate-official-examples.ps1`,
   `tools/official-examples.config.psd1`, and `tools/module-ui.ps1`.
8. The user's availability for G0-G13. Reviews may be scheduled in batches, but approvals remain
   project-specific.

## Plan Audit Findings

Audited 2026-07-30 before implementation through four concurrent roles:
spec/doctrine alignment, acceptance-bar/proof altitude, toolchain feasibility, and sub-phase
decomposition. Three parallel Explore agents performed the first three roles while the coordinating
agent performed decomposition within the four-slot team limit.

Verdict: **judgement calls to review; no open questions**. Fourteen derived fixes and five
independently revertible judgement-call fixes were applied. The plan remains `approval: pending`
and no implementation or public mutation was performed.

### Derived Fixes Applied

1. **Promotion now follows approval.** Added one shared lifecycle: reconcile and prove in the
   release-source/staging worktrees, stop at the human gate, then apply and commit only an approved
   slice to the public release-candidate branch. This removes shorthand that could copy a project
   before the user saw it.
2. **Performance proof now has a real target.** Added a shared pre-change numeric graph budget,
   heavy-node share, settled sample window, and interaction-responsiveness test. CPU wall time is
   explicitly separated from GPU timing and VRAM attribution.
3. **Exclusions gained an executable rail.** The existing promotion script cannot report deletion
   of a project merely removed from its allowlist, so 6B now requires an exact-set census and a
   containment/recoverability-checked whole-project deletion planner before G1.
4. **Release-version and report handling were made falsifiable.** 6B now inventories the highest
   feature/version requirement instead of trusting the stale `0.5.35` config floor, records the live
   host/capability hash, and writes dry-run reports outside both Git worktrees.
5. **Interaction Lab inherited the actual Phase 3 contract.** 6C now tests the defining visual
   language, Style Authority causal chain, live Motion/Burst behavior, sustained spline
   drag/marquee/undo/downstream output, multi-selection/world-local gizmo behavior, stateful reload,
   panel-focus performance floor, and real scaffold interaction.
6. **The UI migration now detects stale authorities.** Templates, skills, knowledge, README, and
   active examples must teach `sui3_*` as the default; v1/v2 references must be removed or explicitly
   historical.
7. **Camera proof now checks positive requirements.** 6D explicitly requires the camera feature and
   interaction declaration, empty `camera_ref`, injected matrix/ray construction, shared state for
   all camera-dependent passes, no exposed camera rows, and aligned color plus real auxiliary output.
8. **Motion/project criteria can no longer pass on static output.** Industrial Lattice and Strata
   require content-asserted nonzero temporal change. Strata also preserves and remeasures its
   approved Draft 480x720/approximately-60-Hz renderer state and known Features proxy/hotspot.
9. **StreamDiff Workflows were split and made mechanism-specific.** 6I.1-6I.6 each have an
   independently committed source/proof record, a falsifiable behavior/control comparison, and
   fresh-process isolation where engine profiles require it.
10. **Autopsia's retired Y proxy was removed.** Conversion count is diagnostic only. Each pad must
    agree with the independent host Properties contract across pointer, reticle, published/durable
    value, and the real effect-producing consumer at asymmetric points.
11. **StreamDiff Canvas now proves the producer and lifecycle.** 6M requires raw-pass plus final
    quadrant alignment, observable hold/render-N/re-hold execution, and staged whole-app VRAM/shared-
    pool observations without false per-node attribution.
12. **Final release audit scope now matches its claims.** 6N separately checks exact project set,
    tracked secrets, relative Markdown links, file-size thresholds, asset/license rights, and
    version compatibility instead of treating the existing validator as if it already covered them.
13. **Clean-clone evidence is bound to the candidate.** Representative outputs are regenerated from
    the exact release commit with file hashes, and critical interactions are replayed or proven
    byte-identical to the approved slice.
14. **Mega-phases gained independent seams.** 6C, 6G, 6H, 6I, 6M, and 6N now have bounded
    one-to-two-sitting slices with explicit stop conditions, while their named human gates retain
    the intended review cadence.

### Judgement-Call Fixes Applied - Review These

1. **Replaced Phase 1's blanket topology with a role-specific Phase 6 matrix.** Show-ready looks
   retain Scene Group, Group Output, 4-8 controls, and preset requirements; Strata/Living Room keep
   their current zero-Group-Output standalone contract; tools and technique specimens receive named
   exemptions. Alternative not taken: force the old gallery-era Group Output/preset topology onto
   every project, or retire the prior standard without a replacement. Revert by removing the matrix
   and restoring the original "Phase 1 minimum where applicable" sentence.
2. **Chose a persistent release-source branch/worktree.** The plan uses
   `phase-6-public-refresh` rooted at fetched private `origin/main`, with accepted overlays committed
   there, rather than a throwaway clone. Alternative not taken: an ephemeral clone with a separate
   patch ledger. Revert in 6A, Pre-Authorizations, Files Summary, and Dependencies.
3. **Chose `projects/camera_reference/` for the camera example.** A loadable saved project is easier
   to discover and proves real Fly/Orbit interaction immediately. Alternative not taken: a loose
   `examples/` Module fragment. Revert the 6D location bullet and Files Summary entry.
4. **Excluded `Laser_Calibration_Grid` from the public creative Canvas.** The private calibration
   tool is preserved, but it cannot appear in creative construction/proof under the workspace's
   diagnostic-imagery prohibition. Alternative not taken: keep it disabled inside the public
   project. Revert the 6M exclusion bullet/criteria if policy changes, without changing the rest of
   the Canvas review.
5. **Required exact-commit clone plus operator/interactive relaunch isolation.** Sentinel exposes
   project load but no restart-app IPC action, and prior StreamDiff profile transitions crashed.
   The plan uses an operator restart or verified interactive `/IT` task between risky loads.
   Alternative not taken: reuse one process and accept cross-profile crash/state contamination.
   Revert only the 6I/6N relaunch clauses.

### Open Questions

None. Topographic HUD, Autopsia inclusion, StreamDiff Canvas naming, unresolved source overlays, and
the final push are intentionally resolved by their existing human gates rather than left as plan
ambiguities.

### Considered And Accepted

- The requested include/exclude lineup and conditional Autopsia decision are faithfully represented.
- G0-G13 are genuine hard stops; automation cannot change `approval: pending` to approved.
- Fetch plus a clean worktree and explicit overlay commits can preserve the dirty main checkout.
- Live Sentinel 0.5.51 exposes the planned project load, compile, health, profile, capture, viewport,
  UI-control, diagnostic, and capability-discovery surfaces.
- One-StreamDiff-project-at-a-time review and explicit engine precision/pack documentation match the
  current product guidance.
- Face Collage, Living Room SDF, Cloth Lab, and Scientific Organism already had meaningful visible
  or behavioral gates; the shared performance and readiness additions strengthen rather than
  replace them.
