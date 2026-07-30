# Living Room SDF

Living Room SDF is a model-free, modular 3D scene and a practical reference for
editing a structured SDF composition in Sentinel. Six authored Modules separate
architecture, furnishings, materials, lighting, rendering, and grading. The
final grade remains the direct image endpoint inside one flat Scene Group.

## Requirements

- Sentinel 0.5.33 or newer
- A DirectX 11 GPU
- No AI model or TensorRT engine pack

Open `living_room_sdf.sentinel`. The saved `Daylight` look is ready immediately;
all Module paths are relative and bundled with the project. Every pipeline node
preview is visible by default, and the project contains no Group Output.

## Furnishings plan editor

Open `LR Furnishings` to work in the top-down authored sui3 Canvas.

- Left-click selects one logical furnishing assembly.
- Left-drag moves the selected assembly. Sofa cushions, table decor, and other
  sub-parts stay attached to their parent furnishing.
- `MOVE` and `ROTATE` choose the transform tool; `M` and `T` are shortcuts.
- `SNAP` toggles grid snapping; `S` is the shortcut.
- Middle-drag pans the plan and the mouse wheel zooms around the pointer.
- `FIT` or `F` restores the authored plan framing.
- `RESET` restores the selected furnishing; `RESET ALL` restores every furnishing.

The plan derives its world span from the live Canvas aspect ratio, so furniture is
not stretched when the panel changes shape. Selection is host-owned, edits use the
viewport transaction path, and the 12-record furnishing state is durable across
project saves and node presets.

Project-scoped node presets:

- `Conversation Plan` restores the authored layout.
- `Offset Sofa Study` restores a visibly shifted sofa assembly, including durable
state rather than only ordinary parameters.

## Lighting desk

Open `LR Lighting` for the full-bleed sui3 lighting Canvas. The left side is an
aspect-correct room plan drawn from the live Architecture and Furnishings records;
the thin cool/warm rings show the six emitted light records in spatial context.
The right-side sliders directly control window daylight, practical lamps, ambient
fill, and shadow softness, so their changes flow through `Light Records` into the
final SDF renderer. This view intentionally has no pan or zoom.

The Lighting Canvas and the exposed Scene Group controls are alternate control
surfaces for the same member parameters. The saved project deliberately avoids a
one-way expression from the group back onto `LR Lighting`, because that would
overwrite changes made in the authored Canvas. Native two-way parameter binding is
deferred until Sentinel exposes a proper bidirectional bind contract.

`LR Architecture` is a control-free sui3 plan surface. Middle-drag pans and the
wheel zooms the plan; exact room, entry, floor, art, and pendant dimensions stay
in Properties. Its 13-record PNode output remains the source of truth for the
Lighting desk and final renderer.

## Scene controls and looks

The `LIVING ROOM // DIRECT-MANIPULATION SCENE` group exposes the controls intended
for live use: render detail, ambient occlusion, daylight, practical lights,
exposure, bloom, and renderer quality. Camera framing lives on the renderer's
built-in camera.

Scene Group presets:

- `Performance` — 960x540, 64 ray steps, lighter AO
- `Fidelity` — 1280x720, 112 ray steps, stronger AO
- `Daylight` — bright window-led material review
- `Warm Evening` — practical-light conversation view
- `Gallery` — restrained, desaturated media-wall view
- `Material Study` — stronger AO and saturation for surface review

## Camera

`LR SDF Renderer` uses its built-in camera directly. Keep **Camera Ref** empty and
use the renderer's internal camera position, target, field of view, and viewport
navigation controls for review framing.

## Remix guide

1. Adjust or replace a producer Module while preserving its typed data contract.
2. Use the plan editor for object-specific layout changes and ordinary parameters
   for broad authored offsets.
3. Save reusable furnishing arrangements as project-scoped node presets.
4. Save complete lighting, internal-camera, grade, and quality states as Scene Group presets.
5. Use `LR Cinematic Grade` directly as the standalone project output.

The renderer is intentionally a consumer: furnishing identity, selection, and edit
logic stay in `LR Furnishings`, while the final PNode records flow downstream.

## Runtime proof

Recall the plan-editor states and scene looks, operate the renderer's native
camera, and capture the final grade with a live health/graph bundle. Generated
proof media is intentionally not distributed with the project.

## Component map

There is no external media source and no model engine dependency.

| Component | Type | Receives | Publishes or contributes |
| --- | --- | --- | --- |
| `LR_Architecture` | Module | authored plan edits | room-shell and opening records |
| `LR_Furnishings` | Module | authored selection and spatial edits | furniture object records |
| `LR_Materials` | Module | authored material controls | material records |
| `LR_Lighting` | Module | architecture and furnishings records | lighting records and lighting-plan preview |
| `LR_SDF_Renderer` | Module | architecture, furnishings, materials, and lighting | native-camera SDF color/depth render |
| `LR_Cinematic_Grade` | Module | renderer texture | final reviewed program texture |

Study the separation between plan editors, typed construction records, and the
camera-owning renderer. Define new semantic objects and relations for a new
space rather than copying this room.
