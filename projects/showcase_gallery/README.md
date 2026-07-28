# Showcase Gallery

`showcase_gallery.sentinel` is the public portfolio switcher for Sentinel's seven aesthetic examples. It keeps each original graph intact inside one flat Scene Group and collects the groups wirelessly through a single groups-mode Mux.

> **High-VRAM review project:** the Gallery loads all seven looks and their engine-backed pipelines into one process. Use the canonical standalone projects under `projects/` for normal distribution and lower-VRAM systems. Each standalone contains one Scene Group and one Group Output, with no Gallery Scene Switcher.

## Use it

1. Load `showcase_gallery.sentinel` in Sentinel 0.5.33 or newer.
2. Select `Gallery_Scene_Switcher`.
3. Use the seven `select/<look>` actions, or set **Selected Scene Group** directly.
4. Adjust **Fade Time** for cuts or crossfades. **Solo Upstream** should remain enabled so nonselected looks are suspended.

The default is **Living Room SDF** at 1280 x 720 with a 0.75 second fade. The allow-list is pinned to the seven group entity ids so unrelated groups added during remixing do not silently enter the show.

## Bound controls

The gallery uses Sentinel 0.5.35+ parameter binds for shared editable values. Its 51 curated Scene Group controls are bidirectionally bound to their member parameters, so edits from a group control or the member's Properties row remain synchronized and undo as one change.

The Strata Composition Desk also has eight direct controller-to-consumer bind networks, and the Desert Warp Deck has twelve. Warp 1 and Warp 2 modes intentionally remain independent named enum button grids on Dada Render; they are not bound through the Warp Deck, which preserves direct mode selection without integer-slider fallbacks.

Expressions remain only where the relationship is genuinely computed: LFO and Conductor motion, scaled/offset mappings, palette fan-out into hidden implementation parameters, and other derived modulation. Dedicated Canvas consoles are not duplicated wholesale at Scene Group level; each group exposes only its stable remix surface.

### Fruit Motion Console

Open `Fruit_LFO` for the full-bleed motion instrument. Its four live waveform
lanes drive prompt position, motion energy, camera drift, and pulse. Each lane
has direct speed, amplitude, and waveform controls; the header adds Master Rate
and Mute, while the right rail provides the Motion Bias XY pad and momentary
Burst trigger. These 16 Canvas controls write the real `Fruit_LFO` parameters
and are intentionally not repeated on the Scene Group.

The console follows its panel rather than stretching a fixed texture. The
gallery proof covers both a 923 x 213 wide dock and a 207 x 154 compact dock;
compact mode abbreviates lane and action labels while preserving every hit
target. `Fruit_Scene` remains the canonical 1280 x 720 renderer.

The Fruit Scene Group carries three gallery-local whole-group presets:

- **Live Fill** — three-clone Flythrough, continuous interval capture, hero
  camera.
- **Frozen Gallery** — single-clone Orbit, explicit slot 0, interval capture
  off, StreamDiff held.
- **Performance** — two-clone Fruitfall, reduced scale and lifecycle rate,
  StreamDiff frame skip 2. This is the saved active preset.

The project-scoped **Four Lane Flight** Motion Console preset and **Transit
Chamber** renderer preset also remain available. The renderer preset includes
its durable card-state payload.

## Looks

| Look | Runtime | Defining feature | Proof |
| --- | --- | --- | --- |
| Living Room SDF | Model-free | Data-driven interior, plan editors, internal renderer camera | [PNG](proof/living_room.png) |
| Face Collage | Engine-backed | StreamDiff, MediaPipe, accumulation, editorial clone layers | [PNG](proof/face_collage.png) |
| Fruit Atlas Scatter | Engine-backed | StreamDiff, matting, depth, atlas capture, 3D fruit tunnel | [Output](proof/fruit_atlas.png) / [Console](proof/fruit_motion_console.png) |
| Topographic HUD | Model-free | Modular texture/data lanes and scientific operations display | [PNG](proof/topographic_hud.png) |
| Strata | Model-free | Layered marble, blob, wire, marks, and composition desk | [PNG](proof/strata.png) |
| Desert Totem | Model-free | Procedural sculpture workstation with internal renderer camera | [PNG](proof/desert_totem.png) |
| Industrial Lattice | Model-free | Compact infinite structural field with tunable ray-march quality | [PNG](proof/industrial_lattice.png) |

Face Collage and Fruit Atlas require the same official engine packs documented by their standalone project READMEs. All other looks compile and run without model packs.

## Import behavior

Sentinel's project importer merges pipelines, links, and relative Module paths, but intentionally does not merge annotations or Scene Group presets. The gallery therefore recreates seven flat groups around the imported graphs and bakes each standalone project's active preset into its imported nodes. `tools/repair-showcase-gallery-imports.ps1` performs that deterministic bake and removes only stale expressions that referenced the source project's old Scene Group id; internal LFO and control-output expressions remain live. The three Fruit presets above are gallery-local restorations and must be preserved when that look is re-imported.

Each group has exactly one Group Output. The gallery itself does not add an eighth Group Output because its Mux is the final switchable output and must not be collected as another look.

## Proof

`proof/runtime-switching.json` records an Industrial-to-Topographic crossfade at the beginning, midpoint, and completion. It also records a 2.5 second freeze test: the selected Topographic final post and gallery Mux advanced 151 frames, while the nonselected Face and Fruit StreamDiff pipelines advanced zero frames.

[`proof/panel_collection.png`](proof/panel_collection.png) is the Phase 5
same-extent review of all seven authored panels inside the Gallery. At
923 x 213 they form one instrument family: black fields, white and gray
construction lines, compact scientific labels, thin rules, and sparse orange
state accents. Each panel remains distinct in information hierarchy rather
than collapsing into a repeated template.

For the complete authored UI, selection, picking, durable state, spline, and gizmo reference, use [`../interaction_lab`](../interaction_lab/). Interaction Lab is deliberately linked rather than included in this aesthetic Mux.

## Remix

- Edit a look in its standalone project, save a representative active Scene Group preset, re-import, and rerun the repair script.
- Keep Scene Groups flat. Nested groups are outside the official-example contract.
- Keep exactly one Group Output per aesthetic group.
- Do not add duplicate top-level control UIs; each standalone graph remains the authority for its own controls.
