# Showcase Gallery

`showcase_gallery.sentinel` is the public portfolio switcher for Sentinel's seven aesthetic examples. It keeps each original graph intact inside one flat Scene Group and collects the groups wirelessly through a single groups-mode Mux.

## Use it

1. Load `showcase_gallery.sentinel` in Sentinel 0.5.33 or newer.
2. Select `Gallery_Scene_Switcher`.
3. Use the seven `select/<look>` actions, or set **Selected Scene Group** directly.
4. Adjust **Fade Time** for cuts or crossfades. **Solo Upstream** should remain enabled so nonselected looks are suspended.

The default is **Living Room SDF** at 1280 x 720 with a 0.75 second fade. The allow-list is pinned to the seven group entity ids so unrelated groups added during remixing do not silently enter the show.

## Looks

| Look | Runtime | Defining feature | Proof |
| --- | --- | --- | --- |
| Living Room SDF | Model-free | Data-driven interior, plan editors, shared cameras | [PNG](proof/living_room.png) |
| Face Collage | Engine-backed | StreamDiff, MediaPipe, accumulation, editorial clone layers | [PNG](proof/face_collage.png) |
| Fruit Atlas Scatter | Engine-backed | StreamDiff, matting, depth, atlas capture, 3D fruit tunnel | [PNG](proof/fruit_atlas.png) |
| Topographic HUD | Model-free | Modular texture/data lanes and scientific operations display | [PNG](proof/topographic_hud.png) |
| Strata | Model-free | Layered marble, blob, wire, marks, and composition desk | [PNG](proof/strata.png) |
| Desert Totem | Model-free | Procedural sculpture workstation with shared cameras | [PNG](proof/desert_totem.png) |
| Industrial Lattice | Model-free | Compact infinite structural field and camera switcher | [PNG](proof/industrial_lattice.png) |

Face Collage and Fruit Atlas require the same official engine packs documented by their standalone project READMEs. All other looks compile and run without model packs.

## Import behavior

Sentinel's project importer merges pipelines, links, and relative Module paths, but intentionally does not merge annotations or Scene Group presets. The gallery therefore recreates seven flat groups around the imported graphs and bakes each standalone project's active preset into its imported nodes. `tools/repair-showcase-gallery-imports.ps1` performs that deterministic bake and removes only stale expressions that referenced the source project's old Scene Group id; internal LFO and control-output expressions remain live.

Each group has exactly one Group Output. The gallery itself does not add an eighth Group Output because its Mux is the final switchable output and must not be collected as another look.

## Proof

`proof/runtime-switching.json` records an Industrial-to-Topographic crossfade at the beginning, midpoint, and completion. It also records a 2.5 second freeze test: the selected Topographic final post and gallery Mux advanced 151 frames, while the nonselected Face and Fruit StreamDiff pipelines advanced zero frames.

For the complete authored UI, selection, picking, durable state, spline, and gizmo reference, use [`../interaction_lab`](../interaction_lab/). Interaction Lab is deliberately linked rather than included in this aesthetic Mux.

## Remix

- Edit a look in its standalone project, save a representative active Scene Group preset, re-import, and rerun the repair script.
- Keep Scene Groups flat. Nested groups are outside the official-example contract.
- Keep exactly one Group Output per aesthetic group.
- Do not add duplicate top-level control UIs; each standalone graph remains the authority for its own controls.
