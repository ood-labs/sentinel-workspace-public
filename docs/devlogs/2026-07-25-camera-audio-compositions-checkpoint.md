---
type: devlog
date: 2026-07-25
status: checkpoint
approval: pending
summary: "Checkpoint the internal-camera contract, audio-classifier evidence, and authored composition library before the default-example UI/camera refresh"
---

# Camera, Audio, and Composition Library Checkpoint

## Outcome

Captured the current reusable work as a save point before a follow-on agent
modernizes the default examples, especially their authored UI and 3D camera
integration. This checkpoint is not a phase boundary and does not mark the
audio classifier or example refresh complete.

## Camera authoring contract

- Added `knowledge/internal-camera-template.md` as the canonical authored-3D
  camera contract.
- Reinforced the same rule across the workspace manuals, module-authoring and
  modular-scene-authoring skills, feature map, module guide, scene-system guide,
  creative exploration goals, and the procedural-building camera template.
- Normal 3D Modules now have one explicit default: native internal camera,
  `features: [camera]`, `viewport.interactions: [camera]`, empty `camera_ref`,
  injected matrices in every camera-dependent pass, and Fly saved as default.
- External `camera`/`camswitch` ownership is reserved for multiple separate 3D
  renderer nodes that genuinely need a shared viewpoint or show-level cuts.

## Audio-reactive work

- Preserved the Pulse2 2D classifier follow-up: inline SuperFlux computation,
  generation-safe historical feature reads, and the shipped zero-cost path
  when flux moments are not used.
- Preserved the separability study, second scored candidate, diagnostics update,
  and the detailed 2D devlog. The existing acceptance miss remains documented;
  this checkpoint does not reinterpret it as passing.
- Excluded Python bytecode and disposable inhibition-sweep output/log files from
  version control. The scored 2D evidence referenced by the devlog remains.

## Authored compositions and techniques

- Added the current authored Module library: analysis proxies, discovery and
  forensic systems, phase-lattice studies, performance instruments, procedural
  ledger components, signal/territory studies, and post-processing modules.
- Added `saved_ledger_composition.sentinel`, which references the reusable
  `pd_*` construction, audit, memory, and performance modules.
- Preserved the latest Scientific Organism and StreamDiff Brush Canvas project
  state, including the brush canvas maximum-rate hold interaction and current
  saved UI/camera state.

## Verification

- Sentinel was reachable in the interactive desktop.
- All 76 newly added Modules passed Sentinel's real offline `compile_check`
  with no shader errors or lints.
- The changed `pulse2_analyzer` and StreamDiff `Pattern_Canvas` Modules also
  passed `compile_check` with no errors or lints.
- Project and score JSON was parsed locally, paired manuals/skills were checked
  for consistency, and `git diff --check` passed.

## Still in progress

- A follow-on agent should audit and refresh the shipped/default examples,
  prioritizing authored Canvas UI behavior and migration of every 3D renderer to
  the canonical internal-camera template.
- The Pulse2 2D classifier still has its documented criterion-1 delta miss and
  its console-verdict display work remaining.
- The newly checkpointed composition library should be curated during the
  example refresh: promote strong reusable modules, consolidate overlaps, and
  retire weak or redundant experiments deliberately rather than losing them
  before review.
