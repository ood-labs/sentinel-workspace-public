# TouchDesigner New Project

A compact Sentinel recreation of the classic TouchDesigner starter graph:

```text
Hermite Signal -> Signal to Texture ----+
                                        v
Jellybeans Image -> Vertical Displace -> Geometry Pass -> Out
```

The example is intentionally small, but every node exposes a useful
intermediate preview.

## What it demonstrates

- A full-panel, responsive scientific signal scope with crisp Scientifica
  labels, ticks, and a left-scrolling Hermite trace.
- A typed structured-buffer signal converted into a floating-point texture.
- Animated vertical image displacement driven by that texture.
- A procedural SDF cube at world origin, textured from the displaced image.
- Perspective-occluded X/Y/Z axes and world-coordinate labels.
- Host-owned selection and an Interaction Lab-style transform gizmo.
- A deliberately transparent Geometry Pass output feeding a final Out node,
  matching the starter graph's pass-through behavior.

## Use

Load `touchdesigner_new_project.sentinel`.

Open **Hermite Signal** to inspect the animated graph. The Canvas follows the
panel size and increases its integer glyph scale as the panel grows.

Open **Geometry Pass** for the 3D viewport:

- Click the cube to select it.
- Press `1`, `2`, or `3` for translate, rotate, or scale.
- Press `4` to switch world/local space.
- Drag the colored gizmo handles.
- Use the native Fly camera controls to inspect the scene.
- Press Escape to cancel an active transform.

The saved cube transform is position `(0, 0, 0)`, rotation `(0, 0, 0)`, and
uniform scale `1`.

## Runtime expectations

No model or engine pack is required. The project uses one image source and
five authored Modules. It was compile-checked and live-proved at 1280x720 with
all active nodes healthy at approximately 57-60 cooks per second.

The bundled `images/jellybeans.png` file is the only media dependency. Module
paths and the image path are relative to the project, so the example is
portable.

## Component map

| Component | Type | Receives | Publishes or contributes |
| --- | --- | --- | --- |
| `Jellybeans_Image` | Image source | `images/jellybeans.png` | portable source texture |
| `Hermite_Signal` | Module | authored controls and time | typed Hermite signal data |
| `Signal_to_Texture` | Module | Hermite signal | displacement texture |
| `Vertical_Displace` | Module | jellybeans image and displacement texture | vertically displaced image |
| `Geometry_Pass` | Module | displaced image | interactive geometry presentation |
| `Out` | Module | geometry pass | final reviewed texture |

No model engine pack is required. Study the signal-to-texture boundary and
purposeful operator decomposition, then build new operators for the current
problem instead of copying this starter graph.
