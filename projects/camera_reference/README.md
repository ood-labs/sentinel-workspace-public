# Native Camera Reference

This focused project is the shortest correct starting point for an authored 3D
Module in Sentinel. Its almost-empty graph contains one renderer, uses
Sentinel's native internal camera, and publishes camera-aligned **Color** and
**Depth** outputs.

## Open and navigate

Open `camera_reference.sentinel`, then double-click **Native Camera Reference**.

- Fly is the saved default.
- Hold RMB and drag to look.
- Use WASD to move and the wheel to change movement speed.
- Press Tab while the preview is active to toggle Sentinel's host-owned Orbit
  mode.

The renderer contains no scene objects and performs no raymarch. It intersects
each native-camera ray with an analytic ground plane, then draws only a fading
grid on a true black field with red X and blue Z origin axes. This keeps the example cheap while
making translation, rotation, orbit target, scale, and depth alignment easy to
judge. A lightweight edge-adaptive color pass smooths the grid independently;
the Depth output remains the untouched analytic camera result.

## Authoring contract

The bundled Module declares `features: [camera]` and
`viewport.interactions: [camera]`. Its `camera_ref` remains empty. The plane
rays come from `_InvViewProjMatrix` and `_CameraPos`. Both outputs come from the
same camera-dependent scene pass.

Do not add a Camera node for a single 3D renderer, several passes inside one
Module, or a renderer followed by post-processing. Use an external camera only
when separate renderer nodes genuinely need one synchronized viewpoint or
show-level camera switching.

No engine pack is required.
