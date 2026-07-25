---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2C2
status: in-progress
approval: pending
summary: "2C2 - console display proven audio-driven; region interaction built but event delivery unproven"
---

## Done

### Criterion 1 (display is audio-driven, not decorative) — MET

`modules/pulse2_console`: a display spectrogram deliberately separate from the
detector's whitening (whitening is tuned for onset separation and reads as flat grey
to a human). Chain is log rebin → per-display-bin running-peak equalisation → dB map
→ gamma. Palette is the workspace monochrome instrument look, not Magma/Inferno.

Proof, `captures/2C2_console_v3_temporamp.png` (1985x862 native panel render):
- Content follows the source: `hats_only_150` puts energy in the upper third with a
  black lower third; `four_on_floor_128` puts substantial energy in the lower third.
- Not a static/tiled pattern: left and right halves are provably non-identical
  (max abs diff 232/255).
- Tempo ramp 120→132 shows kick-onset spacing tightening monotonically across the
  window (236, 233, 235, 233, 233, 232 px ≈ 1.7% over 4.1 s), matching the ramp rate.

Three display defects found and fixed, all mine:
1. **Point sampling.** 384x192 history over a ~2000x860 panel is ~4.5x magnification,
   so real audio rendered as blocks and read as synthetic. Now bilinear on both axes,
   with the hop pair interpolated only when both taps are inside the retained window
   (otherwise it straddles the ring cursor and blends newest against oldest).
2. **Degenerate max-reduce at the bottom of the log axis.** At 23.4 Hz/bin the
   25–200 Hz span is 31% of display height but only ~8 source bins, so a max-reduce
   repeated one bin across ~7 rows and painted a solid white block. Rows narrower than
   one source bin now interpolate.
3. **Double compression.** The dB map is already the perceptual step; gamma 0.45 on
   top rendered a −20 dB bin at 79% brightness and collapsed the image to near-binary.
   Default is now gamma 1.0 / range 60 dB.

History raised 384→768 hops (~2.05 s → ~4.1 s) so a full bar is visible at once.

A vision check on the first capture asserted the halves were "pixel-for-pixel
identical" and the image a synthetic placeholder. That claim was testable and false
(max abs diff 232). It did point at the genuine blockiness, which is what got fixed.

### The console↔analyzer cycle — resolved

Sentinel **rejects** the data cycle: with `pulse2_analyzer/Trace → console` in place,
adding `console/Regions → analyzer` fails with "Cannot create link: type mismatch or
cycle detected". Confirmed live, not assumed.

Resolved with **control outputs + expressions**, which the host evaluates outside the
graph. The console publishes the three lane spans in Hz (`rgn0_lo_hz` … `rgn2_hi_hz`)
from a dedicated buffer element; `sentinel_expression set` binds them onto the
analyzer's own region parameters. Verified live: console `rgn0_hi_hz` = 187.5 (the
200 Hz seed quantised through bin 8) propagated to the analyzer parameter.

This is the better division anyway — the console keeps reading the picker's OWN flux
and threshold for its mini-traces instead of re-deriving them and risking a display
that quietly disagrees with the detector it exists to explain.

**Expressions are currently CLEARED on purpose.** With them bound, the scorer's direct
writes to `rgn*_hz` would be overridden every frame, so a drag on the panel would
silently change scoring configuration — the same class of bug as the enum-default
incident in 2C1. Re-apply for interactive use with:
`sentinel_expression set path=/sentinel/pipelines/pulse2_analyzer/parameters/rgn0_lo_hz expression='ref("pulse2_console/control_outputs/rgn0_lo_hz")'` (and the other five).

Also fixed: the two remaining `default: "Rectangular"` string enum defaults in the
analyzer manifest, now `default: 0`. They happened to resolve correctly (index 0) but
were the same fragile pattern that already cost one full corpus run.

## Not done — 2C2 is INCOMPLETE

- **Criterion 2 (a human can DO the placement) — NOT PROVEN.** The interaction is
  implemented (drag reduction in `events.hlsl`, durable header, live drag rectangle in
  `render.hlsl`), and it compiles and runs. But **zero viewport events are reaching the
  module**: I added `dbg_events` / `dbg_lastev` control outputs that latch the running
  event total and last type/phase, and both stay at 0.000000 after `CLICK_AT` and
  `DRAG_AT`. So the handler is untested, and the drag does not yet move a region.
  Unresolved between three causes, none eliminated:
  (a) my screen-coordinate mapping for the panel is wrong — I estimated the window
      scale from a screenshot because no IPC command reports client size, so the
      injected pointer may be landing outside the panel entirely;
  (b) `DRAG_AT`'s `imgui_injection` path may not feed the module viewport event ring
      at all, only ImGui widgets;
  (c) the manifest `viewport.input` declaration may need something beyond what
      `modules/cryo_console` (a known-working events module) declares — though the two
      declarations are currently identical.
  The next step is to compare against `cryo_console` live to isolate (b) from (a)/(c).
- **Criterion 3 (durable) — PARTIAL.** `sentinel_viewport action=state` reports
  non-zero captured bytes (352, 11 elements, `regions_prev`). Save/close/reopen
  byte-identity and undo-of-a-drag are NOT tested, and cannot be until placement works.
- **Criteria 4 and 5 — IMPLEMENTED, NOT ASSERTED.** Region bands, `_DeltaTime`-scaled
  firing flash (`exp(-dt/tau)`, so the ramp is identical at 20 Hz and 60 Hz), and
  per-region flux-vs-threshold mini-traces all render — amber bands and white traces
  are visible in the live window screenshot. Neither has a vision check taken during
  playback yet.
- **Criterion 6 — NOT RUN.** `./tools/module-ui.ps1 validate` and the 640x360 /
  1600x900 extent re-check have not been done.

## Next

Isolate the event-delivery failure against `cryo_console`, then finish criteria 2–6.
2C2 is human checkpoint 1 — stop for review once complete, do not roll into 2C3.
