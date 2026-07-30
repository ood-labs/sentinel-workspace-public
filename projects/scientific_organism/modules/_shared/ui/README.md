# Scientific UI helpers

The `sui3_*` headers are the current shader-native UI foundation for authored
Module viewports. They use the shipped Scientifica bitmap glyph data, pixel-space
geometry, and structural chrome that stays independent from rollover state.
Legacy `scientific_ui.hlsli` and `sui_v2.hlsli` remain only for compatibility
with older saved Modules; do not start new work from them.

Included primitives:

- shared scientific dark palette, semantic axis colors, panels, grids, rules, rings, and hard-edged wells;
- crisp Scientifica glyph and integer rendering;
- value-aware rails, toggles, XY pads, bank cells, and readouts;
- responsive pixel-space drawing whose layout derives from the live panel extent.

To use it from a sibling Module project:

```hlsl
#include "../_shared/ui/sui3_controls.hlsli"
```

Declare matching controls under `viewport.controls` in the Module manifest. The
manifest rectangle is normalized viewport space; multiply it by the live
`_Resolution` before passing the rectangle to `sui3` drawing helpers.

The kit deliberately has no application-side dependency. It is reusable authored HLSL, not a Sentinel feature or native widget library.

On Sentinel 0.5.32 or newer, a standalone authored interface can occupy the complete pipeline panel and render at the live panel extent:

```yaml
panel:
  mode: canvas
  output: UI
  resolution: follow_panel
```

Canvas retains the dock tab but removes host chrome below it. The shared template uses this contract by default; remove the `panel` block when targeting an older build or a standard preview window.
