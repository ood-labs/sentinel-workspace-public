---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2C2
status: in-progress
approval: pending
summary: "2C2 stage 1 - console spectrogram display is audio-driven and legible; interaction stages not yet built"
---

## Done

**Criterion 1 (display is audio-driven, not decorative) — met.**

Built `modules/pulse2_console`: a display spectrogram deliberately separate from the
detector's whitening (whitening is tuned for onset separation and reads as flat grey
to a human). Chain is log rebin → per-display-bin running-peak equalisation → dB map
→ gamma. Palette is the workspace monochrome instrument look, not Magma/Inferno.

Also extracted `modules/_shared/pulse2/regions.hlsli` as the single region contract and
refactored `pulse2_analyzer` onto it, so the console and the detector cannot drift on
what a region means.

Proof, `captures/2C2_console_v3_temporamp.png` (1985x862 native panel render):
- Content follows the source: `hats_only_150` puts energy in the upper third with a
  black lower third; `four_on_floor_128` puts substantial energy in the lower third.
- Not a static/tiled pattern: left and right halves are provably non-identical
  (max abs diff 232/255).
- Tempo ramp 120→132 shows kick-onset spacing tightening monotonically across the
  window (236, 233, 235, 233, 233, 232 px ≈ 1.7% over 4.1 s), which matches the
  ramp rate. A static pattern cannot produce that.

Three real display defects found and fixed, all mine:
1. **Point sampling.** 384x192 history over a ~2000x860 panel is ~4.5x magnification
   on both axes, so real audio rendered as blocks and read as synthetic. Now bilinear
   on both axes, with the hop pair interpolated only when both taps are inside the
   retained window (otherwise it straddles the ring cursor and blends newest against
   oldest).
2. **Degenerate max-reduce at the bottom of the log axis.** At 23.4 Hz/bin the
   25–200 Hz span is 31% of the display height but only ~8 source bins, so a
   max-reduce repeated one bin across ~7 rows and painted a solid white block.
   Rows narrower than one source bin now interpolate instead.
3. **Double compression.** The dB map is already the perceptual step; gamma 0.45 on
   top rendered a −20 dB bin at 79% brightness and collapsed the image to near-binary.
   Default is now gamma 1.0 / range 60 dB.

History raised 384→768 hops (~2.05 s → ~4.1 s) so a full bar is visible at once.

A vision check on the first capture asserted the halves were "pixel-for-pixel
identical" and the image a synthetic placeholder. That specific claim was testable and
false (max abs diff 232). It did however point at a genuine legibility problem — the
blockiness above — which is what actually got fixed.

## Not done — 2C2 is incomplete

Criteria 2–6 are **not** implemented: region placement by click-drag via
`viewport.interactions: [events]`, durable regions in `state_buffers`, firing-flash
feedback, per-region mini-traces, and `./tools/module-ui.ps1 validate`.

The console↔analyzer data cycle is still unresolved: the console must publish
`Regions` to the analyzer while reading the analyzer's `Trace`. Fallbacks if Sentinel
rejects the cycle — merge the console into the analyzer as a second output, or have
the console compute display-only traces.

`modules/pulse2_analyzer/regionsetup.hlsl` still authors regions from parameters
(the 2C1 path); 2C2 stage 2 replaces its writes with the console's edits.

## Next

2C2 stage 2: durable regions + real click-drag placement, resolving the data cycle.
2C2 is human checkpoint 1 — stop for review once complete, do not roll into 2C3.
