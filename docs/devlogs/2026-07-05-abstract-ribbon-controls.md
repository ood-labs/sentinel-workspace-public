---
type: devlog
status: complete
session_start: "15:35"
session_end: "17:51"
phase: "modular-scene-authoring / abstract reference build"
subphase: "ribbon controls correction"
approval: approved
summary: "Converted the abstract poster ribbon into a controllable data-path lane, added signal-driven animation, and fixed Y-up placement handles"
note_created: abstract-ribbon-controls
updated: 2026-07-05
---

# 2026-07-05 - Abstract Ribbon Poster: controllable ribbon path

## Goal

Respond to user feedback that the abstract poster looked good but failed the modular/editable bar
set by the FUI dashboard. The specific gap was the hero ribbon: it still owned its form internally
and exposed only broad shader knobs, while the smaller objects had placement records. Also fix the
inverted Y behavior on XY placement controls.

## Work Done

- Preserved the previous abstract poster work first:
  - `27234eb Allowlist modular scene projects`
  - `8c2035c Refactor abstract poster to data-driven modules`
- Inspected `projects/fui_dashboard/` as the reference control architecture: signal bus, shared
  control sources, previewable data lanes, layout generators, path stages, and expression-driven
  motion.
- Added `abstract_ribbon_path`, a generator that emits a previewable `Ribbon Path` `PNode` buffer.
  It exposes semantic Y-up handles for the ribbon form: top lip, left shoulder, left belly, lower
  tip, right belly, right lip, inner throat, inner fold, width profile, fold position, path phase,
  wave, breath, and scale.
- Reworked `abstract_ribbon` into a renderer that consumes `Ribbon Path` records rather than
  owning a hidden hardcoded curve.
- Added `abstract_signal`, adapted from the FUI dashboard signal-bus pattern, with `pulse`,
  `sweep`, `beat`, and `slow` control outputs plus a meter preview.
- Registered five live `sentinel_expression` drivers for rib phase, highlight drift, width
  breathing, path wave amount, and path breathe amount.
- Fixed the placement-control convention in `abstract_shape_gen` and `abstract_triangle_gen`:
  point pads are now artist-facing Y-up values, converted to UV/Y-down only at record emission.
- Tuned the new ribbon defaults back down from the first oversized data-path pose and baked those
  values into the manifests.
- Updated `projects/abstract_ribbon_poster/PLAN.md` to document the new graph, expression bus,
  ribbon data lane, and Y-up handle convention.
- Saved a Sentinel checkpoint and proof bundle at
  `projects/abstract_ribbon_poster/checkpoint_ribbon_controls/`.

## Decisions Made

- Use the FUI dashboard as the editability bar, not just the final still image.
- Treat the hero ribbon as a data lane: path generator first, material renderer second.
- Keep user-facing placement controls Y-up, even when renderers consume UV/Y-down.
- Add a dedicated signal node so motion authority is visible in the graph and swappable later.
- Accept the current v3 image as a good starting state while acknowledging the scene is still less
  deeply composed than the FUI dashboard.

## Approvals & Locks

- User accepted the resulting direction as "fine", noted it still felt bare-minimum relative to the
  FUI dashboard, but agreed it got there quickly and looks strong.
- Session committed the control correction as `b2034d4 Add controllable ribbon path to abstract
  poster`.

## Issues Encountered

- The first data-path ribbon pose was too large and too inflated. Fixed by tuning through the new
  semantic path handles rather than returning to hidden shader coefficients.
- Sentinel preserved old point2D Y values across reload, so after changing the generator convention
  to Y-up, live Y values had to be reset to their inverted defaults once.
- A quick state-tree call accidentally used a doubled leading slash, but Sentinel accepted it and
  the intended value was corrected in the following explicit batch.
- The earlier "data-driven" pass did not go far enough: `abstract_shape_gen` exposed many handles,
  but the hero ribbon still had no real input contract. This was a design miss, not a compiler bug.

## Next Steps

- If this poster gets another pass, split the remaining hard-object `abstract_shape_gen` into
  smaller semantic lanes instead of one catch-all record generator.
- Consider promoting the ribbon path/material pair into the reusable library after it gets a second
  use case.
- Add a visual graph annotation or Scene Group around `abstract_signal -> abstract_ribbon_path ->
  abstract_ribbon` so the artist-facing control surface is obvious in Sentinel.
- The Y-up handle convention should be treated as a default for future scene generators.

## Cross-References

- [[2026-07-05-fui-dashboard-cloner-kit]] - reference workflow for the signal bus, previewable
  data lanes, and higher editability bar.
- `projects/abstract_ribbon_poster/PLAN.md` - current scene graph and lane contracts.
- `projects/abstract_ribbon_poster/checkpoint_ribbon_controls/summary.md` - proof bundle summary.
- Commits: `27234eb`, `8c2035c`, `b2034d4`.
