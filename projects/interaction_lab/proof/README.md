# Interaction Lab proof

Verified live in Sentinel 0.5.33 on 2026-07-14. All six Module pipelines compiled and processed at interactive frame rate with healthy status.

## Canvas and responsive layout

Every authored Canvas reported a non-zero `content_size` exactly equal to `render_size` after resize:

- UI Kit: 703 x 643
- Font Sampler: 450 x 1226
- UI Style Tuner: 1704 x 1235
- Spline Editor: 517 x 643
- Gizmo Lab: 517 x 643

The PNGs in this folder are direct pipeline captures at those live render sizes. `ui-style-tuner.png` is the Dense Instrument state; `ui-style-airy.png` is the Airy Review preset.

## Spline interaction, downstream data, and undo

A real pointer drag moved knot 2 from `(0.3600, 0.3000)` to `(0.4045, 0.3420)`. The `Sampled Path` records changed in the same cook and the linked `Spline_Output` image changed by 0.360484%. One `Ctrl+Z` restored every anchor and the downstream output returned to an exact 0% image diff from the baseline.

`Spline Default Wave` restores knot 2 to `(0.3600, 0.3000)` with Path Weight 2.0. `Spline Offset Wave` restores `(0.4045, 0.3420)` with Path Weight 3.5. Both recalls applied the complete 3072-byte durable state payload with no skipped fields.

## Gizmo picking, edit, state, and undo

The synthetic provider pick at normalized `(0.70, 0.60)` hit visible object 7 through the real two-frame asynchronous ray-query path. A real pointer drag on the rendered X handle moved object 7 from `(0.7250, 0.0000, -0.1047)` to `(1.2806, 0.0000, -0.1047)` while host selection remained object 7. The descriptor pivot and durable Scene Objects buffer agreed. One `Ctrl+Z` restored the original transform and advanced the durable upload counter.

`Gizmo Grid` restores object 7 to x = 0.7250. `Gizmo Offset Lead` restores x = 1.2806. Both recalls applied their full 1024-byte durable state payload with no skipped fields.

## Scene Groups

The UI, spline, and gizmo stations are independent, flat control-only Scene Groups. Disabling the UI station bypassed only UI Kit, Font Sampler, and UI Style Tuner; the spline and gizmo stations remained enabled and healthy. Re-enabling restored all six pipelines. No Scene Group contains another Scene Group.

Interaction Lab intentionally has no Group Output because it is a tool/data reference rather than a final scene texture. See the project README for controls and preset names.
