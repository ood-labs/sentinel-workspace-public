---
type: phase
phase_number: "1"
title: "Official Examples Modernization"
status: planned
approval: pending
summary: "Modernize the eight official Sentinel workspace examples into portable, interactive, preset-driven showcases of the complete 0.5.33 authoring system."
---

# Phase 1 - Official Examples Modernization

## Overview And Motivation

Sentinel 0.5.33 can author substantially more than the current aesthetic example projects demonstrate. Authored Modules now support responsive Canvas panels, shader-rendered controls, ordered viewport events, parameter gestures, durable state buffers, host selection, asynchronous picking, four-phase edit transactions, shared cameras, camera switching, identity-aware node presets, Scene Group controls, whole-group presets, Group Outputs, and groups-mode Mux switching.

The public example set already contains strong visual and graph architectures, but most were created before those surfaces shipped. This phase upgrades the examples without flattening their distinct identities or forcing every feature into every project. The collection as a whole must demonstrate the platform's breadth:

- `interaction_lab`: authored UI, selection, picking, state, spline editing, and transform gizmos;
- `living_room_sdf`: direct manipulation of a data-driven 3D scene, shared cameras, and Scene Group control;
- `face_collage`: tracking-driven generative composition with persistent clone edits;
- `fruit_atlas_scatter`: AI generation, atlas capture, selectable 3D cards, and curated/live modes;
- `topographic_hud`: a 2D control surface, signal bus, editable data nodes, and Conductor-ready motion;
- `strata`: a modular composition desk with shared macros and editable plate layout;
- `desert_totem`: a procedural sculpture editor with safe domain-warp presets;
- `industrial_lattice`: a compact beginner-facing camera, preset, and Scene Group example.

Authoring and proof happen first in the private `sentinel-workspace` repository. Only verified, portable content is promoted into the sibling `sentinel-workspace-public` repository. No push is part of this phase unless the user separately authorizes it.

## Governing Contracts

The acceptance bar is the behavior specified in these workspace contracts, not the existence of references to them:

- `knowledge/ui-authoring.md`: rendered and manifest control rectangles match, controls respond to real pointer input, Canvas output follows the panel, and UI remains legible at multiple extents.
- `knowledge/module-pipeline.md`: viewport events use the declared ABI, state survives serialization, selection returns real descriptors, picks hit visible objects, and edits visibly modify the running scene as one undoable transaction.
- `knowledge/scene-system.md`: Scene Groups contain the intended nodes, presets restore whole-scene state, shared cameras actually drive bound renderers, and Group Outputs are switchable through a groups-mode Mux.
- `knowledge/performance-proof.md`: health and frame progression are live, profiles expose no unexplained hotspot, and captures show the actual final pipeline rather than a mock or disconnected preview.

The traceability table in Verification maps these requirements to transcript-provable criteria.

## Problem Statement

### Before

- Interaction Lab is the only example with the complete authored UI and viewport interaction stack.
- Living Room is the only aesthetic example with a real Scene Group and whole-group presets.
- No official example intentionally demonstrates portable project-scoped node presets.
- The Living Room drag prototype performs custom shader picking and stores edits in a texture, so selection is not host-owned and edits are not durable project/preset/undo state.
- Face Collage is absent from the public repository and its private project still carries obsolete module folders.
- Several project documents describe tooling limitations that no longer exist.
- The public Living Room bundle contains historical numbered module copies instead of only the active bundle.
- Public promotion is manual and has no automated absolute-path, dead-module, generated-file, or portability gate.

### After

- All eight examples satisfy one official-example readiness standard while preserving project-specific visual identities.
- Every aesthetic show has a top-level Scene Group, a Group Output, curated controls, safe group presets, and useful project-scoped node presets.
- Direct manipulation is host-backed where object identity is meaningful and deliberately omitted where it would be artificial.
- Stateful object edits survive save/reload and node-preset recall, participate in undo, and have live MCP proof.
- 3D examples use shared Camera nodes; multi-view examples demonstrate Camera Switcher behavior.
- Every public project loads from a clean clone with relative paths, current documentation, declared engine requirements, and representative proof.
- A final gallery imports the aesthetic examples as switchable Scene Groups and visibly changes looks through a groups-mode Mux.

## Scope Fence

This phase does not:

- add or modify Sentinel application, MCP server, plugin, CUDA, TensorRT, or installer source;
- invent a new native widget, selection provider, preset format, or graph serialization format;
- require every project to use every available feature;
- replace existing artistic direction with one universal monochrome skin;
- redesign StreamDiff, tracking, matting, depth, atlas, camera, or Scene Group internals;
- add new proprietary assets or redistribute engine packs;
- push either repository or rewrite Git history without separate authorization.

## Deliverables

| ID | Feature | Primary tools/actions | Status |
| --- | --- | --- | --- |
| D1 | Official-example standard and promotion rails | PowerShell validators, Git, `compile_check` | Planned |
| D2 | Interaction Lab reference hardening | `sentinel_viewport`, `sentinel_preset`, Scene Groups | Planned |
| D3 | Living Room direct-manipulation editor | controls, selection, picking, state, edit, cameras | Planned |
| D4 | Face Collage public interactive instrument | param gestures, selection, state, presets | Planned |
| D5 | Fruit Atlas Director and card editor | atlas, controls, selection, cameras, presets | Planned |
| D6 | Topographic HUD control console | Canvas UI, control outputs, expressions, Conductor | Planned |
| D7 | Strata composition desk | Canvas UI, param gestures/selection, presets | Planned |
| D8 | Desert Totem sculpture workstation | selection, state, camera switcher, safe presets | Planned |
| D9 | Industrial Lattice compact official example | camera, Scene Group, presets, documentation | Planned |
| D10 | Public showcase gallery and clean-clone release proof | Group Output, groups-mode Mux, proof bundles | Planned |

## Shared Official-Example Standard

Every aesthetic example (`living_room_sdf` through `industrial_lattice`, including `face_collage`) must meet all applicable requirements:

1. One top-level Scene Group contains the complete active look.
2. One Group Output receives the actual final texture and makes the look importable into the gallery.
3. The Scene Group exposes approximately 6-10 performance/show controls selected for visible leverage, not every implementation parameter.
4. At least three Scene Group presets exist, including a safe `Performance` default. A `Fidelity` preset is required for GPU-heavy 3D examples.
5. At least two project-scoped node presets exist for the nodes users are expected to remix. Stateful-editor examples must include one preset that restores visibly different durable state.
6. 3D scenes use a shared Camera node. Projects with meaningful fixed views use multiple Camera nodes through a Camera Switcher.
7. Authored UI uses the shared geometry/typography/interaction foundation but applies a palette and information hierarchy appropriate to the project.
8. Direct manipulation uses `param_gestures` for simple parameter-backed handles or selection + descriptors + state buffers + edit transactions for object collections.
9. The saved project contains only active bundled modules and portable relative paths. No shader caches, recovery data, provider secrets, local capture sessions, or machine paths ship.
10. Each project has a user-facing README, a compact proof bundle, current engine requirements, and a short remix guide.

Interaction Lab is exempt from the single-final-output requirement because it is a multi-station feature laboratory, but it must demonstrate control-only/nested Scene Groups and portable node presets.

## Sub-Phase 1A - Foundation And Promotion Rails

This is substrate only; it does not deliver a refreshed user-visible example by itself. Sub-phases 1B-1J deliver the visible and executing experiences.

### Contract

| Field | Value |
| --- | --- |
| Parameters | Private root, public root, official project allowlist, shared dependency allowlist, exclusion globs, expected Sentinel minimum version |
| Response schema | Per-project `{project, files_checked, active_modules, orphan_modules, absolute_paths, generated_stale, compile_results, portable, errors[]}` plus aggregate pass/fail |
| UE APIs | N/A. Sentinel is a C++/HLSL/ImGui application; use filesystem/Git checks and Sentinel MCP only. |
| Primary actions | Fix normalized manifest hashing in `tools/module-ui.ps1`; add official-example validation and promotion scripts; define the readiness standard |

### Implementation Details

- Normalize manifest text to LF before hashing so generated UI validation is invariant across Git line-ending policy.
- Add `tools/validate-official-examples.ps1` to inspect only the eight approved projects and their declared shared dependencies.
- Detect absolute paths, missing project files, missing referenced Module directories, unreferenced bundled Module directories, shader caches, captures/recovery/provider files, stale generated UI headers, missing README/proof, and manual/private-only artifacts.
- Use saved pipeline `project_dir` values as the active-module authority; report historical module folders as orphans.
- Add `tools/promote-public.ps1` with dry-run by default. Promotion copies an explicit allowlist, excludes local artifacts, produces a source/destination diff, runs validation in the public checkout, and never pushes.
- Document the private-authoring -> proof -> promotion -> public-clean-clone workflow.

### Pass Criteria

1. On the current CRLF checkout, `module-ui.ps1 validate` passes for the unchanged committed UI examples and the normalized hash equals the generated declaration.
2. A seeded fixture containing an absolute `C:/Users/...` project path, an orphan module folder, and a shader cache fails validation with all three concrete findings; removing them makes the same fixture pass.
3. Promotion dry-run lists only allowlisted public files and changes neither checkout. A real promotion into a disposable public-worktree copy produces a validator-clean tree whose normalized content matches the private source for every promoted text file.
4. The standard explicitly distinguishes required features from project-specific exemptions, so Industrial Lattice is not failed for lacking meaningless object picking and Interaction Lab is not failed for lacking one final Group Output.

## Sub-Phase 1B - Interaction Lab Reference Hardening

### Contract

| Field | Value |
| --- | --- |
| Parameters | `UI_Kit`, `Font_Sampler`, `Spline_Editor`, `Spline_Output`, `Gizmo_Lab`, `UI_Style_Tuner`; three station annotations; project-scoped preset names |
| Response schema | `info.panel`, `viewport.info`, `viewport.objects`, `viewport.selection`, `viewport.pick`, `viewport.edit`, `viewport.state`, preset `applied[]/skipped[]`, Scene Group inventories |
| UE APIs | N/A. Use Module manifests/HLSL, graph Scene Group actions, and Sentinel MCP. |
| Primary actions | Convert stations to control-only Scene Groups, add stateful node presets, improve README recipes, refresh proofs |

### Implementation Details

- Preserve the existing visual and interaction behavior as the reference baseline.
- Convert the three labeled graph bays into control-only Scene Groups without changing their internal links.
- Add curated project presets for UI density/style, at least two spline arrangements, and at least two gizmo object arrangements.
- Demonstrate that state-buffer payloads travel with node presets by recalling visibly different spline/gizmo states.
- Add exact user and MCP walkthroughs for controls, selection, pick, edit, state inspection, preset recall, and Canvas resizing.

### Pass Criteria

1. A human can resize each open Canvas and still see complete, aligned controls; `content_size` and `render_size` converge and no control's rendered rectangle separates from its hit region.
2. A real pointer drag visibly moves a spline knot, changes the downstream `Spline_Output`, and one undo restores both editor and downstream output.
3. A synthetic MCP pick hits a visible Gizmo Lab object; an edit visibly moves it; `objects`, `selection`, and `state` agree on the selected id and durable transform.
4. Recalling two different project-scoped stateful presets visibly produces two different spline or gizmo arrangements after save/reload, not merely different parameter readback.
5. The three station Scene Groups can be independently enabled/disabled without corrupting the remaining stations, and nested/group preset behavior is documented with live proof.

## Sub-Phase 1C - Living Room Direct-Manipulation Editor

### Contract

| Field | Value |
| --- | --- |
| Parameters | Logical furnishing id, transform offset/rotation, tool mode, snapping, reset, exposed lighting/grade/quality controls, four review cameras |
| Response schema | Logical object descriptors, selection ids, pick result, durable transform-state inventory, edit transaction state, camera selection, group preset values |
| UE APIs | N/A. Use `LR_Furnishings` Module buffers/HLSL, Camera/Camera Switcher pipelines, Scene Group and preset MCP. |
| Primary actions | Replace custom texture picking with host selection/state/edit; create a plan editor Canvas; add shared cameras and expanded presets |

### Implementation Details

- Treat sofas, chairs, tables, media unit, plants, and decor groups as logical objects; do not expose every SDF sub-record as a separately editable furnishing.
- Publish one stable descriptor per logical object and map edits back to all PNode records owned by that object.
- Replace the current persistent texture offsets with a declared structured state buffer so save, undo, and node presets restore transforms.
- Build a themed top-down plan Canvas with Move, Rotate, Reset, and optional Snap controls. Render selected-object outlines from host selection.
- Use four shared Camera nodes for Conversation, Left Side, Media Corner, and Reverse Media, selected through a Camera Switcher. Preserve exploratory fly/orbit behavior.
- Retain Performance/Fidelity and add visibly distinct lighting/material presets such as Daylight, Warm Evening, Gallery, and Material Study.
- Remove historical inactive bundled Module copies and ensure group presets contain portable relative paths.

### Pass Criteria

1. In the running plan Canvas, a human can click a visible chair, see only that logical chair highlighted, drag it to a new location, rotate it, and see the final graded 3D room update correspondingly.
2. One committed drag creates one undo step; undo and redo visibly move the entire logical furnishing assembly without separating its sub-parts.
3. Save/reload and a stateful node-preset recall restore the edited furnishing location exactly; `viewport.state` reports the expected durable record count and bytes.
4. Each named Camera Switcher selection produces the intended visibly different review view, and writes to the bound renderer's local camera do not change the image while the shared camera does.
5. Performance/Fidelity recalls change live render cost and quality as intended; Daylight/Warm Evening recalls visibly change lighting while keeping the scene graph healthy.
6. The public-ready bundle contains only the six active Module folders plus approved shared files, has no private absolute paths, and loads with all six pipelines healthy and frames increasing.

## Sub-Phase 1D - Face Collage Public Interactive Instrument

### Contract

| Field | Value |
| --- | --- |
| Parameters | Face-guide handles, clone id, pin/offset/scale/rotation, delay/history, accumulation, overlay, finish, preset mode |
| Response schema | Face/clone descriptors, clone selection, durable override state, MediaPipe and clone data-port counts, preset recall results, group health |
| UE APIs | N/A. Use Module parameter gestures, structured data, selection/state/edit, MediaPipe, StreamDiff, Scene Groups, and presets. |
| Primary actions | Clean the active graph, add direct manipulation and Collage Director UI, package and promote Face Collage |

### Implementation Details

- Start from the cleaned eleven-node working graph and remove obsolete bundled modules from abandoned branches.
- Add parameter gestures to the procedural guide for head, eyes, and mouth composition controls where they are genuinely parameter-backed.
- Publish stable clone descriptors from the same clone records used to render. Add persistent per-clone pin/offset/scale/rotation overrides without destroying live procedural motion for unpinned clones.
- Build a project-themed Collage Director Canvas for stamp/history, delay, accumulation, overlay, and finish controls.
- Create group presets such as Live Morph, Temporal Echo, Dense Web, Editorial Minimal, and Performance plus node presets for Cutout, Overlay, and Finish.
- Add explicit engine-pack requirements and a no-camera/no-tracking diagnostic explanation to the README.

### Pass Criteria

1. Dragging a visible face-guide handle visibly changes the guide and the subsequent StreamDiff composition; resetting the handle restores the authored default.
2. A human can select a visible clone, pin and transform it, and watch unpinned clones continue moving while the pinned clone retains its edited placement.
3. The pinned clone survives save/reload and stateful preset recall; its descriptor, selected id, and visible transform agree.
4. Live Morph, Temporal Echo, Dense Web, and Editorial Minimal recalls produce visibly distinct running collage behavior, not only different numeric values.
5. From a clean public checkout with required engines installed, the project reaches healthy frame progression through tracking, cutout, accumulation, overlay, finish, and final output. With a required pack deliberately unavailable, the README-described diagnostic is concrete and the app does not crash.
6. The promoted project contains only active modules and no local paths, provider data, reference images, or obsolete multi-StreamDiff artifacts.

## Sub-Phase 1E - Fruit Atlas Director And Card Editor

### Contract

| Field | Value |
| --- | --- |
| Parameters | Live/curated mode, prompt position, capture trigger/slot, selected card id, persistent card transform, scatter seed/spread, camera, preset mode |
| Response schema | Atlas occupancy/cycle state, Slot Occupancy data, card descriptors, selection/pick/edit/state, engine health, preset results |
| UE APIs | N/A. Use Atlas/StreamDiff/Matting/Depth pipelines, authored Modules, cameras, Scene Groups, and MCP. |
| Primary actions | Add Atlas Director Canvas, selectable card transforms, cameras, and live/curated group presets |

### Implementation Details

- Add an authored Atlas Director showing slot occupancy, current prompt/capture state, and Live Fill versus Curated Stills controls.
- Spike and prove the control-output/expression path for momentary StreamDiff/Atlas triggers before committing to the UI architecture; if momentary actions cannot be safely expression-driven, expose the native actions through the Scene Group and keep the Canvas read/control surface to supported parameters.
- Publish one descriptor per occupied atlas slot and layer persistent transform overrides over deterministic scatter placement.
- Add shared Hero, Orbit, and Profile cameras through a Camera Switcher.
- Add Live Fill, Curated Stills, Frozen Gallery, Hero Scatter, and Performance presets.

### Pass Criteria

1. In Live Fill mode, a human sees atlas occupancy advance and the 3D scene populate with newly generated fruit cards; switching to Frozen Gallery visibly stops replacement while the scene continues rendering.
2. In Curated Stills mode, a user can choose a slot, render one still, capture it, and visibly see that exact slot/card update without refilling unrelated slots.
3. A human can select a visible card, move/rotate/scale it, and recall its transform after save/reload; pick ids match occupied slot ids.
4. Camera selections visibly change the view and group presets produce distinct live versus curated behavior while non-selected expensive work is held or bypassed as documented.
5. Matting, depth, atlas, and scene health are live, occupancy data is nonzero, and the final proof shows cutout cards with depth/parallax rather than opaque rectangular placeholders.

## Sub-Phase 1F - Topographic HUD Control Console

### Contract

| Field | Value |
| --- | --- |
| Parameters | Manual/auto signal mode, terrain, node density, layer gains, palette, selected node/label id, persistent offset, cue mode |
| Response schema | Control outputs and active expressions, node/label descriptors, selection/edit state, Conductor status/cue outputs, Scene Group/preset results |
| UE APIs | N/A. Use Module Canvas UI, structured data, expressions, Conductor, Scene Groups, and presets. |
| Primary actions | Turn the signal bus into a themed console, add editable node/label offsets, add cue-ready modes |

### Implementation Details

- Preserve the existing fifteen-node modular graph and three transport lanes.
- Extend or companion the `signal` module with a cyan/orange operations-console Canvas controlling terrain, density, layer mix, palette, and signal authority.
- Keep animation authority visible: manual controls and Conductor/macros publish through control outputs and compiled expressions rather than hidden shader coupling.
- Add stable 2D descriptors and durable offsets for a bounded set of important nodes/labels; do not turn every generated contour sample into an editable object.
- Add Survey, Threat, Night Vision, Minimal, and Performance group presets.
- Replace stale debrief tooling complaints with current user-facing authoring and remix guidance while retaining historical lessons where useful.

### Pass Criteria

1. A human can operate the Canvas controls and visibly change terrain, node density, layer balance, and palette in the final HUD while control-output/expression readback identifies the actual drivers.
2. Selecting and dragging a visible important node or label moves the corresponding rendered element, preserves its data link relationships, and survives save/reload.
3. Switching between manual and Conductor-driven modes visibly changes motion authority without discontinuous jumps or duplicate drivers.
4. Survey, Threat, Night Vision, Minimal, and Performance recalls are visibly distinguishable and retain the shared height-field/data-lane coherence.
5. The final graph remains fifteen semantic content nodes plus only justified control/group/output additions, profiles at the target display rate on the reference machine, and reports no unexplained hotspot.

## Sub-Phase 1G - Strata Composition Desk

### Contract

| Field | Value |
| --- | --- |
| Parameters | Master seed, palette, plate mix, melt/twist/marble warp, panel/focal placement, selected layout record, feature reactivity |
| Response schema | Macro control outputs, expressions, layout descriptors/state, feature data counts, Scene Group and preset results |
| UE APIs | N/A. Use Module Canvas UI, param gestures or bounded selection/state, Features pipeline, expressions, and presets. |
| Primary actions | Turn `strata_control` into a composition desk, add direct plate/layout manipulation, curate looks |

### Implementation Details

- Preserve the plate-system and premultiplied-alpha contracts.
- Upgrade `strata_control` into a gray/red composition Canvas while retaining its control-output role.
- Add direct manipulation for the marble panel/focal composition through parameter gestures; add bounded blob-layout selection only if stable logical records can be exposed without fighting procedural regeneration.
- Make Features-driven thread behavior discoverable and switchable rather than an opaque side chain.
- Add Clean Studio, Melted Chrome, Graphic Poster, Wire Cage, and Performance group presets plus node presets for the macro/control and renderer modules.

### Pass Criteria

1. A human can change master seed, plate mix, and distortion from the Canvas and visibly obtain new coherent compositions without editing shaders.
2. Dragging the visible marble/focal control visibly repositions the intended plate consistently; if blob selection is included, edited logical blobs persist without breaking procedural variation for unedited blobs.
3. Feature reactivity can be visibly enabled/disabled, and the corner-thread response corresponds to nonzero live Features data rather than a disconnected mock.
4. The five curated presets are visibly distinct while preserving premultiplied composition—no black alpha boxes, broken wire continuity, or palette incoherence.
5. Performance preset meets the profile budget on the reference machine and Fidelity/hero proof retains the approved high-quality look.

## Sub-Phase 1H - Desert Totem Sculpture Workstation

### Contract

| Field | Value |
| --- | --- |
| Parameters | Logical part id, transform override, warp macros/slots, surface/deform, camera selection, safety quality preset |
| Response schema | DadaPart descriptors/data counts, selection/edit/state, camera switch state, group preset state, live profile/hotspot reasons |
| UE APIs | N/A. Use authored Module data/state, Camera/Camera Switcher, Scene Groups, presets, and performance proof. |
| Primary actions | Make layout editable, add themed warp deck, add cameras and watchdog-safe presets |

### Implementation Details

- Upgrade the layout preview into a sculptural composition editor using stable logical DadaPart identities and durable transforms.
- Build an ochre/black warp deck around existing control outputs and renderer parameters; do not duplicate warp math.
- Add Hero, Detail, Orbit, and Silhouette cameras through a Camera Switcher.
- Curate Dalí Melt, Cubist Glitch, Monument, Painterly, and Performance presets. Performance must cap combinations known to approach TDR risk.

### Pass Criteria

1. A human can select a visible logical totem part in the editor, move/rotate/scale it, and see the final 3D sculpture update without detaching child primitives.
2. The edited composition survives save/reload and stateful preset recall, with data-port records and visible scene agreeing.
3. Warp deck controls visibly affect the complete distance field coherently, and each named preset produces the intended distinct visual language.
4. Shared camera selections visibly produce hero/detail/orbit/silhouette framings and preserve viewport interaction.
5. An automated bounded sweep of every shipped preset completes without crash/TDR, and Performance stays within its declared profile budget on the reference machine.

## Sub-Phase 1I - Industrial Lattice Compact Official Example

### Contract

| Field | Value |
| --- | --- |
| Parameters | Structure spacing/profile, junction/detail, surface, lighting, fog, camera, quality preset |
| Response schema | Pipeline health/profile, shared camera state, Scene Group controls/presets, Group Output status |
| UE APIs | N/A. Use existing Module HLSL, Camera, Scene Group, presets, Group Output, and proof actions. |
| Primary actions | Package a clean beginner-facing two-node scene with modern cameras, presets, and documentation |

### Implementation Details

- Keep the graph intentionally small; do not invent object picking for an infinite repetition field with no stable unique instances.
- Add one shared camera and curated Hero, Lookup, Deep Grid, and Fly framings if camera switching improves the teaching value.
- Expose a small structural/light/surface control set and add Box Frame, Heavy Steel, Concrete Haze, Fidelity, and Performance presets.
- Update notes to match the current Junctions/Panels/Surface feature set and explain why the example is deliberately compact.
- Bundle root-level modules into the project or prove that the approved public relative dependency layout is portable from a clean clone.

### Pass Criteria

1. A new user can load the project and visibly navigate the infinite lattice with the shared camera without resolving paths or wiring nodes.
2. The exposed controls visibly change member spacing/profile, junction/detail, surface, lighting, and fog as documented.
3. Camera and look presets produce visibly distinct, well-framed states; Performance and Fidelity show the expected quality/cost difference while both remain healthy.
4. The clean public project contains only the required scene/post modules and reaches increasing frames at the documented target resolution.

## Sub-Phase 1J - Showcase Gallery And Public Release

### Contract

| Field | Value |
| --- | --- |
| Parameters | Allowed Scene Groups, selected group, fade time, output resolution/fit, optional camera/engine readiness indicators |
| Response schema | Scene Group inventory, one Group Output per aesthetic group, Mux collection/selection state, per-look health/profile, public validator report |
| UE APIs | N/A. Use project import, Scene Groups, Group Outputs, groups-mode Mux, capture/proof actions, Git, and promotion tooling. |
| Primary actions | Build `showcase_gallery.sentinel`, validate all projects from a clean public clone, prepare local public commit |

### Implementation Details

- Import the seven aesthetic examples as Scene Groups, excluding Interaction Lab from the live look switcher while linking it as the feature laboratory.
- Resolve module-id/path collisions during import without collapsing the original graphs.
- Use one groups-mode Mux as the final switcher and document engine-backed versus model-free looks.
- Ensure non-selected groups freeze and expensive StreamDiff work does not continue unnecessarily.
- Produce a compact representative proof set and update the public root README/example matrix.
- Promote into `sentinel-workspace-public`, validate in a clean worktree/clone, and create a local public-repository commit. Do not push.

### Pass Criteria

1. A human can select every gallery look from the Mux and visibly see the correct final project output; each group has exactly one valid Group Output and invalid/missing groups do not silently masquerade as success.
2. At least one crossfade completes smoothly, and retargeting during a fade continues from the current image without a visible jump.
3. Non-selected groups report frozen/bypassed behavior as designed; only the selected StreamDiff-backed look actively diffuses.
4. Every standalone project and the gallery load from a clean public checkout with no private paths, missing active modules, stale generated headers, or unexpected dirty files.
5. The final proof set visibly contains the defining content of every project—not placeholder colors—including a selectable/editor UI proof where applicable and a final output proof for each aesthetic look.
6. The public repository is locally committed and clean after validation; no network push occurs without separate user authorization.

## Files Summary

### Expected New Files

- `docs/phases/phase-1-official-examples-modernization.md`
- `docs/implementation-plan.md`
- `docs/official-example-standard.md`
- `tools/validate-official-examples.ps1`
- `tools/promote-public.ps1`
- missing project READMEs and project-specific authored control/editor Modules
- `projects/showcase_gallery/showcase_gallery.sentinel` and bundled dependencies

### Expected Modified Files

- `tools/module-ui.ps1`
- active project `.sentinel` files and active Module manifests/HLSL
- shared authored UI/theme files only when a reusable improvement is required
- project notes/debriefs converted or supplemented with user-facing documentation
- public root README/example matrix
- `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` Current Status while this phase is active

### Files That Must Not Change

- Sentinel application source and the `../sentinel` repository
- Sentinel MCP server/proxy source
- plugin manifests or plugin source
- engine packs, model weights, provider credentials, and installation files
- unrelated local creative modules, captures, and recovery data

## Implementation Order

1. 1A - fix validation and establish promotion/readiness rails.
2. 1B - lock Interaction Lab as the reference implementation.
3. 1C - use Living Room as the pilot aesthetic/editor integration.
4. 1D then 1E - modernize the generative instruments, Face Collage and Fruit Atlas.
5. 1F then 1G - modernize the modular 2D systems, Topographic HUD and Strata.
6. 1H then 1I - finish the procedural 3D examples, Desert Totem and Industrial Lattice.
7. 1J - assemble the gallery, run clean-public verification, and prepare the local public commit.

Each sub-phase closes independently with its own devlog, proof, and commit before the next begins. A failed example does not authorize weakening the shared standard; exemptions require a documented semantic reason like Industrial Lattice's lack of stable unique instances.

## Verification Plan

### Proof Stack

1. Static portability: official-example validator, normalized source/public diff, no secrets/absolute paths/orphans.
2. Compiler: `sentinel_pipeline compile_check` on every active Module.
3. Runtime: project load, compile polling, pipeline `info`, healthy status, increasing frames, output formats/resolutions.
4. Data: `get_data_schemas` and `capture_data_port` for real counts/ids/active flags.
5. Interaction: `sentinel_viewport info`, `objects`, `selection`, `pick`, `edit`, and `state`, plus real or injected pointer input.
6. Persistence: save/reload, undo/redo, node-preset recall, and group-preset recall with exact readback and visible image changes.
7. Presentation: Canvas content/render convergence and captures at multiple panel sizes.
8. Performance: graph profile and project-specific Performance/Fidelity comparisons.
9. Visual proof: output captures/proof bundles evaluated against project-specific content assertions, not merely file existence.
10. Release: clean public worktree/clone load and gallery look switching.

### Governing-Contract Traceability

| Contract requirement | Enforced by |
| --- | --- |
| Manifest and rendered controls coincide; real pointer input works | 1B.1-1B.2, 1C.1, 1F.1, 1G.1 |
| Canvas follows panel and stays legible | 1B.1 and each project Canvas visual criterion |
| Selection/picking returns real visible objects | 1B.3, 1C.1-1C.3, 1D.2-1D.3, 1E.3, 1H.1-1H.2 |
| Edits are durable and undoable | 1B.2-1B.4, 1C.2-1C.3, 1D.3, 1E.3, 1F.2, 1H.2 |
| Scene Group presets visibly restore whole looks | every aesthetic project's named preset criterion |
| Shared camera controls bound renderers | 1C.4, 1E.4, 1H.4, 1I.1-1I.3 |
| Group Output/Mux switching executes | 1J.1-1J.3 |
| Live health/performance is real | every project's runtime/profile criterion and 1J.4 |
| Public artifact is portable | 1A.2-1A.3, 1C.6, 1D.6, 1J.4-1J.6 |

## Autonomy And Human-In-The-Loop

### Human-Intervention Points

Human review is batched into two taste checkpoints and one release checkpoint:

1. After 1C, review Interaction Lab plus Living Room together to approve the shared interaction grammar and the rule of project-specific skins.
2. After 1I, review the seven aesthetic projects as one portfolio batch for visual identity, preset naming, and default-look selection.
3. During 1J, approve the final gallery order and authorize any public network push separately. Local promotion and commits do not require this push approval.

Sub-phase completion reviews, automated proofs, and devlogs are self-serve and do not pause implementation unless a hard blocker is reached.

### Gate Tiers

#### Tier 1 - Self-Serve

- compile, health, data-port, viewport, persistence, profile, and portability checks;
- authoring files inside this workspace and the explicitly selected project directories;
- project-local aesthetic iteration within the already approved visual identity;
- project-scoped node presets and Scene Group presets;
- proof captures, recordings, vision evaluation when configured, devlogs, and per-sub-phase commits;
- disposable worktrees/copies used for promotion and clean-clone verification.

Record the result, leave `approval: pending`, and continue to the next planned sub-phase.

#### Tier 2 - Conditional-Proceed

- If vision evaluation is unavailable, proceed with deterministic visual assertions plus local image inspection and flag the missing AI review in the devlog; do not weaken behavioral checks.
- If an authored interaction can be implemented with existing controls, param gestures, selection, state, or events, choose the smallest existing mechanism that satisfies the visible criterion. If none can, stop rather than modify Sentinel.
- If a project's default exceeds its performance budget, tune the `Performance` preset while preserving a separate Fidelity/hero preset. Do not silently lower every preset.
- If a bundled project contains inactive historical modules, remove only folders proven unreferenced by the saved graph and promotion validator.
- If a public/private text diff is line-ending-only, normalize for comparison and proceed; substantive public-only edits must be reconciled explicitly.
- If required official engine packs are missing on the reference machine, install only the documented pack through Sentinel's pack manager and record it. Do not fetch unregistered weights or proprietary assets.
- If the live app is dirty, create a recoverable checkpoint/save before loading an example. If no safe checkpoint can be made, treat it as a hard blocker.

### Pre-Authorizations

- Use the current aesthetic language of each approved example; do not ask for per-control color approval.
- Use the shared authored UI interaction/layout foundation while creating project-specific themes.
- Add Camera, Camera Switcher, Group Output, Conductor, Mux, and authored Module nodes where the phase explicitly calls for them.
- Create and recall project-scoped node presets and whole-group presets.
- Refactor active project-local Module files when necessary to implement descriptors, durable state, controls, or proof.
- Create local commits in both private and public workspace repositories using explicit paths after their respective checks pass.
- Keep Interaction Lab as the canonical technical reference and Industrial Lattice deliberately compact.

### Hard Blockers

- Any required change to Sentinel application, MCP server, plugin, installer, or engine source.
- Any need to alter a shipped serialization/selection/preset contract rather than author within it.
- Inability to preserve a dirty live project before loading an example.
- A licensing or redistribution ambiguity for an asset, font, model, or proof artifact.
- A destructive cleanup whose active/inactive status cannot be proven from the saved graph.
- Git history rewrite, force push, remote push, repository visibility change, or release publication without explicit authorization.
- A visual direction decision that would replace—not refine—an already approved example identity.

## Example Agent Workflow

1. Run `/start-session`; read this phase doc, the relevant project docs, and live capabilities.
2. Confirm the live app can be safely checkpointed before loading a project.
3. Run the official-example validator and capture the project's baseline failures.
4. Snapshot/save the live project state and create a sub-phase devlog with `approval: pending`.
5. Modify only active authored Module/project files; write shaders before manifests.
6. Run offline compile checks, then load/force-reload and poll compile status.
7. Wire and arrange new nodes with local layout operations; preserve the authored graph.
8. Prove real data, viewport behavior, persistence, preset recall, presentation, and performance.
9. Capture project-specific visible proof and verify the content assertions.
10. Save with bundled modules, rerun portability validation, and commit the private sub-phase.
11. At promotion time, run a dry-run diff, promote to the public sibling, validate in a clean worktree, and commit locally.
12. Use `/wrap` per sub-phase; use `/audit` and `/end-session` at the Phase 1 boundary.

## Dependencies

- Sentinel 0.5.33 or newer with the live commands discovered in `sentinel_app capabilities`.
- Installed official engine packs for the engine-backed Face Collage and Fruit Atlas proofs.
- Existing Interaction Lab UI/selection/state reference modules.
- Existing private and public sibling repositories with clean, non-destructive Git workflows.
- A configured vision provider is helpful but not a hard dependency because deterministic visual assertions remain mandatory.
- Completion of each earlier sub-phase's reusable pattern before dependent examples adopt it.
