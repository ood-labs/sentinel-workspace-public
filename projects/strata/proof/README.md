# Strata Composition Bus proof

Program proof was refreshed on 2026-07-27 from the live Sentinel 0.5.49
project. The standalone `strata_control` node now uses a fixed 480 x 270
passive bus preview with zero authored controls; all editing is in Properties.
Feature-toggle and marble-placement captures remain valid for those unchanged
surfaces.

- `clean-studio.png`, `melted-chrome.png`, `graphic-poster.png`, `wire-cage.png`, and `performance.png` show five visibly distinct whole-group looks with intact premultiplied composition.
- `composition-desk.png` is historical evidence for the superseded authored
  desk and is not the current shipping interface.
- `composition-bus.png` is the current 480 x 270 passive preview.
- Current live proof reports Standard panel mode, a 480 x 270 render target,
  and healthy advancing frames for `strata_control`. Module UI validation
  reports zero controls.
- `feature-disabled.png` and `feature-enabled.png` prove that the visible corner thread is driven by the real feature toggle rather than a disconnected mock.
- `marble-focal-shift.png` proves the composition changes when the parameter-backed marble focal moves.
- Live Features data reported fifteen `Corners` records with a current GPU buffer generation.
- The **Performance** preset bypassed Features, reduced renderer AA to one sample, and profiled at approximately 59.7 FPS with the remaining graph healthy.
- All ten authored Module directories passed Sentinel's real offline `compile_check`.
- Project-scoped node presets **Atelier Plate Balance** and **Hero Sculpture** saved with explicit parameter stacks.
- Final structure: ten authored Modules, one Features node, one Group Output,
  one flat Scene Group, zero child groups, seven live exposed controls, five
  recalled group presets, and zero Composition Bus gestures.
