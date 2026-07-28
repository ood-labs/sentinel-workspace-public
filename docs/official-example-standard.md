# Sentinel Official Example Standard

This document is the release-readiness contract for the curated projects in the private `sentinel-workspace` repository and their portable copies in `sentinel-workspace-public`. It supplements the behavioral criteria in [Phase 1](phases/phase-1-official-examples-modernization.md); passing the static validator alone does not prove an example is finished.

## Official Collection

| Project | Teaching role | Required direct manipulation | Exceptions |
| --- | --- | --- | --- |
| Interaction Lab | Canonical authored UI, viewport, selection, state, and gizmo laboratory | Yes, at its spline and gizmo stations | No single final Group Output; uses three flat control-only Scene Groups instead |
| Living Room SDF | Logical-object editing in a modular 3D scene | Furnishings | None |
| Face Collage | Tracking-driven generative editorial composition | None | Deliberately procedural; no clone selection, transform gizmos, or separate Director Canvas |
| Fruit Atlas Scatter | Generative still banking and editable 3D cards | Occupied atlas cards | None |
| Topographic HUD | Modular 2D console, signal routing, and cue-ready motion | Important nodes and labels only | Generated contour samples are not individually editable |
| Strata | Modular plate composition and feature-reactive design | Focal plate controls; bounded blobs only if stable | Procedural blobs without stable identity remain procedural |
| Desert Totem | Procedural sculpture workstation | Logical totem parts | None |
| Industrial Lattice | Compact beginner-facing 3D example | None | Infinite repetition has no meaningful unique object identity |
| Procedural Building System | Modular procedural-construction reference with spatial editors and typed architectural records | Massing, facade feature, and lighting handles | Technical workflow study: the renderer is the primary output and StreamDiff is an optional downstream reference, so no Group Output or preset suite is required |
| Showcase Gallery | Internal seven-look integration and Scene Switcher review fixture | None | Review-only high-VRAM aggregator; validate locally but do not distribute or promote |

An exemption removes only the artificial feature named above. It does not relax health, portability, preset, documentation, or visual-proof requirements.

## Required Project Shape

Every aesthetic project must ship with:

1. exactly one `.sentinel` project file at the project root;
2. one top-level Scene Group containing the complete active look;
3. exactly one Group Output receiving the actual final texture;
4. 6-10 high-leverage controls exposed by the top-level Scene Group;
5. at least three whole-group presets, including `Performance`;
6. at least two project-scoped node presets for nodes a user is expected to remix;
7. a shared Camera for 3D rendering and a Camera Switcher when named fixed views add teaching value;
8. a user-facing `README.md` with engine requirements, controls, presets, remix steps, and diagnostics;
9. a compact `proof/` bundle containing representative final output and interaction evidence;
10. only active project-local Module folders plus explicitly approved shared dependencies.

Interaction Lab replaces items 2-5 with three independently switchable, flat control-only Scene Groups and stateful node presets. It remains subject to the same runtime, persistence, documentation, and portability bar.

Showcase Gallery is not a shipping project. It retains the same integration
shape for internal review: seven flat imported aesthetic Scene Groups, exactly
one connected Group Output inside each group, and one final groups-mode Mux
whose exact allow-list matches those seven groups and enables `solo_upstream`.
It has no nested groups and does not duplicate the imported projects' control
or preset authority. Promotion tooling must refuse it; the standalone projects
are the distribution authorities.

### Technical modular-procedural examples

A technical construction example may replace the final-show requirements with a teaching graph when its purpose is to expose reusable data contracts and editors rather than ship one performance look. It must still provide:

1. a named semantic node for every independently reusable responsibility;
2. typed structured-buffer links whose producer and consumer schemas agree exactly;
3. a meaningful, live preview for every generator, plan, material, lighting, or transform node;
4. spatial Canvas interaction only where direct manipulation is genuinely clearer than Properties;
5. dense numeric and color tuning in ordinary Properties instead of duplicating a fragile slider rail;
6. host selection, exact picking, durable state, and one render/pick/drag coordinate transform for spatial editors;
7. exactly one camera owner, with Fly as the saved default unless a deliberate external camera rig is part of the lesson;
8. explicit display-ready color and structural auxiliary outputs when a downstream consumer needs different representations;
9. a primary non-AI output that remains useful when optional AI engines are unavailable;
10. documentation and proof that distinguish the validated core from experimental downstream branches.

The canonical reference is `projects/procedural_building_system/`, with the reusable construction contract in `knowledge/modular-procedural-systems.md`.

## Interaction Selection Rules

Use the smallest host-supported interaction mechanism that matches the content:

- Use `viewport.controls` for ordinary authored buttons, sliders, toggles, and XY pads.
- Use `viewport.param_gestures` for a small number of parameter-backed handles.
- Use descriptors, host selection/picking, declared state buffers, and four-phase edit transactions for collections of logical objects.
- Derive descriptors and rendered geometry from the same records. A pick id must identify the object the user can see.
- One drag is one undoable transaction. Durable edits must survive save/reload and stateful node-preset recall.
- Do not add picking merely to increase feature count. Content without stable semantic identity should remain parameter-driven.

Authored Canvas controls must render from the same normalized rectangles declared in the manifest, remain legible at multiple panel extents, and report matching nonzero `content_size` and `render_size` under `follow_panel`.

## Preset Rules

- `Performance` is the safe default for expensive projects and must remain healthy at the documented target resolution.
- GPU-heavy 3D examples also provide `Fidelity` so the quality/cost tradeoff is visible.
- Look presets must produce visibly different running output, not just different parameter readback.
- Stateful editors include at least one node preset that restores a visibly different durable arrangement.
- Scene Group presets own whole-look state, including contained pipeline parameters and bypass state. Node presets remain portable remix building blocks.
- Scene Groups must remain flat. Do not place one Scene Group inside another until nested groups are explicitly supported and adopted as part of the product contract.

## Runtime Proof

Proof is collected from the running Sentinel build and must exercise the feature as a user would:

1. `sentinel_pipeline compile_check` passes for every active Module directory.
2. Project load reports no unresolved `project_dir` values.
3. Every active pipeline reports `healthy=true`, increasing `framesProcessed`, a real preview SRV where applicable, and the intended output format/resolution.
4. Structured-data examples prove nonzero real records with `get_data_schemas` and `capture_data_port`.
5. Interactive examples prove real controls, selection, pick, edit, undo/redo, durable state, and save/reload behavior.
6. Preset recalls are paired with captures asserting the intended visible change.
7. `sentinel_graph profile` shows no unexplained hotspot; Performance/Fidelity comparisons record their actual live cost.
8. `proof_bundle` captures the final connected pipeline and Sentinel window. Placeholder colors, disconnected previews, and readback-only assertions do not pass.
9. When configured, vision evaluation checks project-specific visual assertions. If unavailable, deterministic capture assertions and local image inspection remain mandatory.

Compile results are intentionally not inferred by the static validator. Its JSON response lists active modules with `compile_results.status = "not_run"` until the runtime proof slice supplies authoritative compiler evidence.

## Portability And Repository Hygiene

Saved project `pipelines[].parameters.project_dir` values are the authority for active Module folders.

- Project-local modules use relative `modules/<name>` paths.
- Shared root modules are allowed only when listed in `tools/official-examples.config.psd1`.
- Absolute drive, `/Users/`, and `/home/` paths are release failures even when they resolve on the authoring machine.
- Unreferenced bundled Module directories are orphans and are not promoted.
- `captures/`, recovery data, shader caches, checkpoints, provider configuration, `.env` files, compiler outputs, logs, and private debriefs do not ship.
- Project `proof/` is curated evidence, not a dump of local capture sessions.
- Engine packs, model weights, provider credentials, and proprietary source assets are never copied.
- Source and public text files are compared after LF normalization so Git line-ending policy cannot create false drift.

## Static Validation

Validate the full private collection:

```powershell
./tools/validate-official-examples.ps1
```

Validate selected projects and emit machine-readable evidence:

```powershell
./tools/validate-official-examples.ps1 -Projects interaction_lab,living_room_sdf -Json
```

The response includes, per project:

```text
project, files_checked, active_modules, orphan_modules, absolute_paths,
forbidden_artifacts, missing_paths, generated_stale, compile_results,
exemptions, portable, errors, warnings
```

The validator checks the saved graph's static release shape, active-module resolution, project-scoped preset counts, Scene Group/Group Output presence, exposed-control range, normalized generated-UI hashes, documentation/proof presence, and forbidden artifacts. Runtime behavior still follows the proof contract above.

Run the deterministic tooling fixture after modifying validation or promotion logic:

```powershell
./tools/test-official-examples.ps1
```

The fixture first fails on a seeded absolute path, orphan Module, and shader cache, repairs the same project, proves a non-mutating dry-run, then performs a real promotion into a disposable public root and verifies normalized file parity plus destination validation.

## Private-To-Public Promotion

Author and prove changes in the private repository. Promotion is explicit and defaults to dry-run:

```powershell
./tools/promote-public.ps1 -Projects interaction_lab
```

The dry-run lists only:

- the selected official project;
- root README/license files allowed by configuration;
- curated `assets/`, `cues/`, and `proof/` folders;
- Module directories referenced by the saved active pipelines;
- project-local and approved global `_shared` dependencies.

After reviewing the diff, copy and validate locally:

```powershell
./tools/promote-public.ps1 -Projects interaction_lab -Apply
```

Apply mode replaces only the selected destination project and its explicitly referenced root Module directories, compares every promoted file, and runs the official validator in the destination. It never stages, commits, or pushes. Commits use explicit paths after proof; remote push and release publication require separate user authorization.

## Promotion Sequence

1. Preserve or checkpoint dirty live Sentinel state.
2. Validate the selected private project and record its baseline failures.
3. Run compiler, runtime, interaction, persistence, performance, and visual proof.
4. Remove orphans and local artifacts only after the active graph proves they are unused.
5. Run the static validator until the private project passes.
6. Review promotion dry-run.
7. Apply into the public sibling.
8. Validate and load from a disposable clean public worktree/clone.
9. Commit private and public paths explicitly.
10. Do not push without separate authorization.
