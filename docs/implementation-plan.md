# Sentinel Workspace Implementation Plan

## Purpose

This plan governs work in the user-writable Sentinel workspace and its curated public counterpart. Sentinel application and MCP implementation work belongs in their own repositories and is out of scope here.

## Phase Overview

| Phase | Title | Status | Detailed plan |
| --- | --- | --- | --- |
| 1 | Official Examples Modernization | Complete; approval pending | [Phase 1](phases/phase-1-official-examples-modernization.md) |
| 2 | Audio Analysis v2 (`pulse2`) | In progress | [Phase 2](phases/phase-2-audio-analysis-v2.md) |
| 3 | Interaction Lab v2 (Instrument-Grade UI Overhaul) | Planned | [Phase 3](phases/phase-3-interaction-lab-v2.md) |

## Phase 1 - Official Examples Modernization

Modernize the seven existing public examples plus Face Collage into portable, interactive showcases of Sentinel 0.5.33. The work establishes shared readiness and promotion rails, upgrades each project according to its own semantic strengths, and concludes with a groups-mode Mux gallery and clean-public-checkout proof.

### Sub-Phases

| Sub-phase | Outcome | Primary capability | Status |
| --- | --- | --- | --- |
| 1A | Foundation and promotion rails | validation, portability, private-to-public workflow | Complete |
| 1B | Interaction Lab reference hardening | Canvas UI, state, selection, presets, control-only groups | Complete |
| 1C | Living Room direct-manipulation editor | logical selection, durable transforms, cameras, group presets | Complete |
| 1D | Face Collage public instrument | restrained Scene Group controls, tracking, presets | Complete |
| 1E | Fruit Atlas Director and card editor | atlas operations, selectable cards, cameras, live/curated modes | Complete |
| 1F | Topographic HUD control console | Canvas control bus, editable nodes/labels, Conductor | Complete |
| 1G | Strata composition desk | macro UI, plate manipulation, feature reactivity | Complete |
| 1H | Desert Totem sculpture workstation | part editing, warp deck, cameras, safe presets | Complete |
| 1I | Industrial Lattice compact example | beginner graph, shared camera, look/quality presets | Complete |
| 1J | Showcase gallery and public release | Group Outputs, groups-mode Mux, clean-clone proof | Complete; approval pending cold-load crash follow-up |

### MCP And Runtime Surfaces

- `sentinel_app`: `ping`, `status`, `capabilities`, `engine_status`, `load_project`, `save_project`.
- `sentinel_pipeline`: `list_types`, `info`, `compile_check`, `compile_status`, `force_reload`, `get_data_schemas`, `capture_data_port`.
- `sentinel_graph`: Scene Group actions, annotations, links, cameras/group placement, profile, local layout.
- `sentinel_viewport`: `info`, `objects`, `selection`, `pick`, `edit`, `state`.
- `sentinel_preset`: project-scoped save/list/recall/update/delete/rename plus live bundle/copy actions when exposed.
- `sentinel_expression`: visible control-output and Conductor drivers.
- `sentinel_capture`: `capture_at`, `proof_bundle`, `checkpoint`, recordings/sweeps as appropriate.
- `sentinel_conductor`, Camera, Camera Switcher, Group Output, Atlas, and groups-mode Mux where specified by the phase doc.

### Dependencies

1. Live Sentinel 0.5.33 capability surface.
2. Interaction Lab reference modules and shared UI foundation.
3. Official engine packs for Face Collage and Fruit Atlas proof.
4. Private `sentinel-workspace` as the authoring source and sibling `sentinel-workspace-public` as the curated target.
5. Safe checkpointing of any dirty live Sentinel session before project loads.

### Implementation Order

1. Establish validation and promotion rails.
2. Lock the reference behavior in Interaction Lab.
3. Prove the full pattern in Living Room.
4. Refresh generative examples: Face Collage, then Fruit Atlas Scatter.
5. Refresh modular 2D examples: Topographic HUD, then Strata.
6. Refresh procedural 3D examples: Desert Totem, then Industrial Lattice.
7. Assemble the showcase gallery and validate the public repository from a clean checkout.

The detailed phase doc is the acceptance contract. A sub-phase is not complete because files compile or proof artifacts exist; its visible and behavioral criteria must execute in the running application.

## Phase 2 - Audio Analysis v2 (`pulse2`)

Build a reusable GPU audio analysis system that every future audio-reactive project consumes,
replacing the hand-tuned `modules/cryo_pulse`. The phase delivers adaptive-whitened SuperFlux onset
detection, click-to-place spectral region isolation, a multi-feature classifier for coincident hits,
and comb-filter tempo estimation with a dual-loop beat PLL.

The ordering deliberately departs from the source research: the scoring harness is built **first and
is blocking**. The CRYOGRAM session established that a detector tuned by eye, with no way to measure
whether a change helped, produces circular work and undetected regressions.

### Sub-Phases

| Sub-phase | Outcome | Primary capability | Status |
| --- | --- | --- | --- |
| 2A1 | Frozen corpus and onset-export contract | seeded synthesis, hash manifest, `Hits` data output | Planned |
| 2A2 | Scorer and committed baseline | File-mode playback, onset F1, BPM error, CMLc/AMLc | Planned |
| 2B | `pulse2_analyzer` core detector | adaptive whitening, SuperFlux, lookahead peak-picking | Planned |
| 2C1 | Region masks and evaluation | programmatic regions, scorable without UI | Planned |
| 2C2 | Spectrogram console | Canvas panel, click-to-place regions, durable state | Planned |
| 2C3 | Lateral inhibition | cross-lane contamination suppression | Planned |
| 2D | Multi-feature classifier | centroid, flatness, decay; coincident-hit separation | Planned |
| 2E1 | Comb Filter Matrix and tempo | 2D dispatch, tempo prior, harmonic suppression | Planned |
| 2E2 | Dual-loop PLL, confidence, free-wheel | beat phase, honest uncertainty, soak stability | Planned |
| 2F | Project, documentation, portability | bundling, clean-path load, reproducible scores | Planned |

Audited before implementation by four parallel agents (spec-alignment, acceptance-bar,
toolchain-feasibility, decomposition). The audit found that the original 2A was silently blocked:
`modules/cryo_pulse` publishes no `data_outputs`, so MCP-polled counters cannot supply the per-hit
timestamps a +/-25 ms F1 window requires. See the phase doc's Plan Audit Findings section.

### MCP And Runtime Surfaces

- `sentinel_pipeline`: `list_types`, `create`, `info`, `compile_check`, `compile_status`,
  `force_reload`, `get_data_schemas`, `capture_data_port`.
- `sentinel_state`: Audio In source/device/`fft_size` control, diagnostics subtree, control-output reads.
- `sentinel_graph`: `add_link`, `profile` (rolling `cook_hz`), `focus`, `place_relative`.
- `sentinel_viewport`: `info` for delivered-gesture proof on the console panel.
- `sentinel_capture`: `pipeline` captures for visual proof; `checkpoint` at sub-phase boundaries.
- `sentinel_vision`: content assertion on the spectrogram capture where configured.

### Dependencies

1. Sentinel 0.5.49 or newer with `audio` in `list_types` and per-data-input generation uniforms.
2. Python 3 for corpus generation and scoring.
3. `modules/cryo_pulse` present and unmodified as the scoring baseline.
4. Shared authored UI headers under `modules/_shared/ui/`.

### Implementation Order

1. 2A1 corpus and onset-export contract.
2. 2A2 scorer and committed baseline. Nothing else begins first.
3. 2B core detector.
4. 2C1 region masks and evaluation.
5. 2C2 spectrogram console; first human taste checkpoint.
6. 2C3 lateral inhibition.
7. 2D multi-feature classifier.
8. 2E1 comb matrix and tempo.
9. 2E2 PLL, confidence, free-wheel; second human taste checkpoint.
10. 2F project assembly and portability proof.

The detailed phase doc is the acceptance contract. A sub-phase is not complete because a shader
compiles or a capture exists; its measured and behavioral criteria must hold in the running
application.

## Phase 3 - Interaction Lab v2 (Instrument-Grade UI Overhaul)

Promote AUTOPSIA's instrument UI language into a shared `sui3_*` kit, consolidate Interaction Lab
from seven stations to four, and rebuild each station so state is carried by structure and live
readout rather than by fill and rollover.

AUTOPSIA deliberately does not use Interaction Lab's shared kit
(`modules/_shared/au_hud/au_text.hlsli:9` records the decision). The refinement therefore lives in
the `au_*` renderers while every lab station is built on the older, more generic `sui_*` layer.
Lifting the lab station-by-station would be fighting the kit, so the kit is replaced first.

Two operator decisions taken at plan time are binding: **hybrid scope** (new kit, three real tools
rebuilt, three demonstration nodes merged into one station with a genuine job) and **amber accent
reserved for meaning**, which overrides the lab's strictly-monochrome precedent.

### Sub-Phases

| Sub-phase | Outcome | Primary capability | Status |
| --- | --- | --- | --- |
| 3A | Baseline, profile ceiling, platform-bug confirmation | captures, profiling, live probes | Planned |
| 3B | `sui3_*` kit and the Style Authority station | pixel-space HLSL primitives, control outputs | Planned |
| 3C | Motion Console rebuilt; `burst` fixed | viewport event hit-testing, meters | Planned |
| 3D | Spline Editor rebuilt | selection, marquee, tangents, undo | Planned |
| 3E | Gizmo Lab rebuilt | host selection, transform handles | Planned |
| 3F | Consolidation, presets, clean-checkout hand-off | preset migration, group audit, portability | Planned |

### MCP And Runtime Surfaces

- `sentinel_pipeline`: `compile_check`, `compile_status`, `force_reload`, `info`, `open_window`.
- `sentinel_graph`: `profile` (rolling `cook_hz`), `focus`, `place_relative`, `auto_layout` as an
  explicit layout checkpoint, Scene Group exposure actions.
- `sentinel_viewport`: `info` for delivered-gesture counts, `state` for durable-state bytes.
- `sentinel_capture`: `capture_at` at two panel extents, `proof_bundle`, `checkpoint`.
- `sentinel_expression`: theme drivers from the Style Authority to the other stations.
- `sentinel_preset`: preset migration and recall verification.
- `sentinel_vision`: content assertion on captures, with a deterministic PNG fallback.

### Dependencies

1. A running Sentinel in the active interactive desktop; Canvas panels need 0.5.32 or newer and
   viewport events need 0.5.30 or newer.
2. `tools/module-ui.ps1` for station validation.
3. `projects/autopsia` present and readable as the frozen reference implementation.
4. An operator available for two hands-on sessions - viewport event injection does not work on this
   build (`docs/state.md:89`), so pointer-gesture proof needs a hand on the mouse.

### Implementation Order

1. 3A baseline and platform-bug confirmation. Nothing else begins first.
2. 3B kit, then Style Authority. Taste checkpoint - a hard stop.
3. 3C Motion Console.
4. 3D Spline Editor.
5. 3E Gizmo Lab.
6. 3F consolidation, presets, batched interaction pass, clean-checkout proof.

The detailed phase doc is the acceptance contract. A station is not complete because it compiles or
a capture exists; its visible and behavioral criteria must hold in the running application, and its
gesture criteria require a recorded hands-on pass.

## Future Phases

No later workspace phase is scheduled yet. Additional examples should enter the public collection only after Phase 1 establishes and proves the readiness standard.

Public promotion of Interaction Lab v2 is deliberately **not** part of Phase 3: Phase 1 remains
approval-pending with an open cold-load follow-up, so promotion is a separate decision.
