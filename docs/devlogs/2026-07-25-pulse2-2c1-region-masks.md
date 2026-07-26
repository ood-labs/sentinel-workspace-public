---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2C1
status: complete
approval: pending
summary: "Region masks in spectrogram coordinates - kick F1 0.909 vs 0.834 fixed-lane, aggregate 0.797"
---

## Done

Detection regions replace 2B's hard frequency split. Regions are authored
programmatically from manifest parameters into a `regions` buffer by
`regionsetup.hlsl`, and `flux.hlsl` reduces each lane as a weighted mean over
its regions. No UI, so this is scorable independently of 2C2.

- **Stored in spectrogram coordinates**, never panel UV. Spans are authored in
  Hz because that is the meaningful unit, then converted to bin indices using
  the producer's own reported bin width (the header the whitening pass captures
  off a verified slot). `spec_to_panel` / `panel_to_spec` in `common.hlsli` are
  the single shared transform for 2C2's render, pick and drag.
- **Rectangular and Gaussian profiles.** The profile shapes the bin axis only;
  the hop axis is always a rectangular gate, because a Gaussian across time
  would weight a hop by how old it is — a property of the display, not the
  audio, which would make one onset score differently depending on when it was
  looked at.

**Pass criterion 1 met.** Kick region over the kick band scores kick F1 **0.909
vs 2B's 0.834**, printed with a delta column against `scores/2B.json`. No pattern
dropped; regression gate PASS. Aggregate 0.797 vs 0.774.

Per-pattern kick gains: `breakbeat_170` +0.214, `kick_snare_coincident_124`
+0.191, `syncopated_funk_105` +0.190, `dense_140` +0.156. With rectangular unit
gain the reduction is exactly the 2B fixed-lane mean, which is how the region
path was proven correct before any profile change: that run reproduced 2B to
three decimals on 8 of 11 patterns.

## Decisions

**Gaussian on the kick region only.** Measured on non-held-out patterns: kick
F1 `breakbeat_170` 0.659 -> 0.857, `dense_140` 0.868 -> 0.974,
`syncopated_funk_105` 0.800 -> 0.971. Tapering the edges suppresses the click and
harmonic bleed a hard band boundary admits. The same profile on the snare and hat
regions did **not** help (`dense_140` snare -0.017, hat unchanged), so those stay
rectangular. The held-out `kick_snare_coincident_124` also gained +0.191 without
being tuned against, which is the evidence that this generalises.

## Issues

**Enum defaults must be the index, not the label.** `default: "Gaussian"` parses
without error and then silently resolves to index 0, so the module ran
rectangular while the manifest read Gaussian. This produced a complete,
plausible-looking corpus table that was simply the wrong configuration — caught
only by reading the live parameter back. Editing a manifest default also does not
reach an already-created pipeline. Both facts are now recorded at the parameter
in `manifest.yaml`.

Consequence for tooling: `score_detector.py` gained `--set NAME=VALUE`, which
re-applies overrides after **every** per-pattern `force_reload` (which resets
parameters to manifest defaults). Setting a parameter once before a run does not
survive.

Snare remains the known deficit, unchanged from 2B and carried to 2C3.

## Next

2C2 - spectrogram console (human checkpoint 1).
