---
name: module-ui-authoring
description: Build responsive interactive Sentinel Module interfaces with viewport controls and events, durable state, selection and gizmos, and full-bleed Canvas or follow-panel presentation. Use when creating shader-rendered control panels, editors, spline tools, transform gizmos, dashboards, or any Module intended to behave like a UI rather than only an effect.
---

# Module UI Authoring

Build the interface entirely as authored Module content. Keep HLSL responsible for presentation and use the manifest for semantic interaction contracts.

Read `knowledge/ui-authoring.md` before implementing. Use `knowledge/module-pipeline.md` when the task needs the full event, selection, state-buffer, or data-port schema.

## Workflow

1. Discover the live build with `sentinel_app ping`, `sentinel_pipeline list_types`, and `sentinel_app capabilities`. Canvas panels require Sentinel 0.5.32 or newer.
2. Choose the interaction level: `viewport.controls` for fixed controls, `events` for custom pointer/keyboard behavior, `param_gestures` for parameter-backed movement, or `selection` plus state buffers for object editors and gizmos.
3. Scaffold with `./tools/module-ui.ps1 new projects/<project>/modules/<name> -Name "<Display Name>"`. The helper vendors its neutral dependencies into the owning project and refuses cross-project or root-module targets.
4. Keep control rectangles and labels in `manifest.yaml`. Run `module-ui.ps1 generate` after every control or label change.
5. Replace the scaffold's placeholder visual language with one appropriate to the current problem. If its generic SUI3 primitives remain useful, render through `../_shared/ui/sui3_controls.hlsli`. Convert generated normalized hit rectangles to pixels with the live `_Resolution`; keep strokes, typography, geometry, and layout measurements in pixel space.
6. For a standalone full-frame panel, declare `panel.mode: canvas`, name the UI output, and choose `panel.resolution: follow_panel`. Keep the selected output pass inheriting root resolution.
7. Write shader files before the manifest, run `module-ui.ps1 validate`, then run the real `sentinel_pipeline compile_check`.
8. Create or force-reload the live Module, poll `compile_status`, and inspect `info` health. For Canvas, verify `info.panel.content_size` and `render_size` converge.
9. Prove the real interaction with viewport input and data/state readback. Capture only after the result settles.
10. Bundle the Module with a saved `.sentinel` project when the example should travel.

## Hard Rules

- Keep this work Module-only unless the user explicitly requests a native Sentinel capability.
- Make the manifest hit rectangle and the rendered rectangle identical.
- Keep hit targets at least 32 pixels tall at the declared default resolution.
- Read momentary feedback from only that control's pressed flag. Do not let hover state recolor shared borders or neighboring controls.
- Drive toggle, slider, and selected-tool visuals from their actual values. Prefer branchless geometry for binary visual states.
- Choose typography, palette, density, and motion for the current project rather than inheriting an example's aesthetic. Preserve every bundled font license.
- Acquire drag handles on pointer-down and retain ownership through commit/cancel. Do not re-pick during a drag.
- Use actual `_Resolution` for projection and hit-testing. A hard-coded design resolution must never distort camera-dependent gizmos.
- Follow Interaction Lab Style Authority exactly for `point2D` and `xypad`: keep the host value unmodified, declare a plain bounding rect, and route all value-to-pixel and pixel-to-value conversion through the project-local `sui3PadPoint` / `sui3PadValue` helpers. Any hand-written `1.0 - value.y` or bare pad `lerp` outside that shared helper is a bug. Prove top and bottom through real viewport drags, parameter readback, published-value readback, and settled captures.
- Render and hit-test 3D rotation handles from the same projected axis-plane basis.
- Scale decay by `_DeltaTime`; Module cook rate is not display rate.
- Do not call an immediate single capture proof of a parameter write. Require a settled frame and live health/readback.

## Canvas Contract

```yaml
panel:
  mode: canvas
  output: UI
  resolution: follow_panel
```

Canvas removes host chrome below the dock tab. `follow_panel` changes the real Module output size continuously. Multi-output Canvas Modules must name `output`; the selected output pass must inherit the root resolution. Users can override presentation from the graph or View menu, and project workspaces persist that choice.

## Validation

```powershell
./tools/module-ui.ps1 generate projects/<project>/modules/<name>
./tools/module-ui.ps1 validate projects/<project>/modules/<name>
```

Then run `compile_check`, poll `compile_status`, inspect `info`, and read `sentinel_viewport info` for the live instance.

Use the Interaction Lab component map and saved graph to study responsive panels, spline editing, selection, and transform gizmos. Reimplement the needed interaction for the current project; do not copy its project-specific Modules unless the user explicitly requests a fork or remix. Never link one project to another project's Module directory at runtime.
