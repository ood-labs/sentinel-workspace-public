# Sentinel Workspace Implementation Plan

## Purpose

This plan governs work in the user-writable Sentinel workspace and its curated public counterpart. Sentinel application and MCP implementation work belongs in their own repositories and is out of scope here.

## Phase Overview

| Phase | Title | Status | Detailed plan |
| --- | --- | --- | --- |
| 1 | Official Examples Modernization | Complete; approval pending | [Phase 1](phases/phase-1-official-examples-modernization.md) |
| 2 | Audio Analysis v2 (`pulse2`) | Planned | [Phase 2](phases/phase-2-audio-analysis-v2.md) |

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
| 2A | Scoring harness and synthetic corpus | deterministic File-mode playback, onset F1, BPM error | Planned |
| 2B | `pulse2_analyzer` core detector | adaptive whitening, SuperFlux, lookahead peak-picking | Planned |
| 2C | Region masks and spectrogram console | Canvas panel, click-to-place regions, lateral inhibition | Planned |
| 2D | Multi-feature classifier | centroid, flatness, decay; coincident-hit separation | Planned |
| 2E | Comb Filter Matrix tempo and beat PLL | 2D dispatch, tempo prior, honest confidence | Planned |
| 2F | Project, documentation, portability | bundling, clean-path load, reproducible scores | Planned |

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

1. Corpus generator, scorer, and committed baseline scores. Nothing else begins first.
2. Core detector, scored against that baseline.
3. Regions and console; first human taste checkpoint.
4. Multi-feature classifier.
5. Tempo and beat PLL; second human taste checkpoint.
6. Project assembly and portability proof.

The detailed phase doc is the acceptance contract. A sub-phase is not complete because a shader
compiles or a capture exists; its measured and behavioral criteria must hold in the running
application.

## Future Phases

No later workspace phase is scheduled yet. Additional examples should enter the public collection only after Phase 1 establishes and proves the readiness standard.
