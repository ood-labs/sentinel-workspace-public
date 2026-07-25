---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2C2
status: in-progress
approval: pending
summary: "2C2 - criteria 1,3,4,6 proven; 2 and 5 partial, two clauses need a human drag"
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

## Criterion re-verification (after the checkpoint)

### A source-mode gap I had missed

During the first criterion-1 pass I set `file_path` and `restart_file` but NEVER
verified `source_mode`. It is an enum where 0 = Device (live loopback) and 1 = File,
and File mode is the only mode in which `file_path` means anything. If the node had
been in Device mode, those captures were recording system audio rather than the
corpus. The timeline argues it was in File mode at the time, but "probably" is not
proof, so criterion 1 was re-run with the mode set explicitly.

### Criterion 1 — MET (re-verified, mode explicit)

| pattern | upper third (HF) | mid | lower third (LF) | HF/LF |
| --- | --- | --- | --- | --- |
| `hats_only_150` | 96.2 | 15.4 | 20.6 | **4.67** |
| `four_on_floor_128` | 112.0 | 83.5 | 129.5 | **0.86** |

Stated diff: **30.0%** mean absolute luminance; **88.5%** of pixels differ by >5%.
Vision assertions: hats_only → "upper third", lower third "mostly dark/empty";
four_on_floor → lower third "contains substantial bright energy", with repeating
bright low-frequency columns. Noted honestly: the model called the upper third
brightest for four_on_floor, which contradicts the pixels (lower 129.5 > upper 112.0);
the clauses the criterion actually needs hold on both vision and measurement.

### Criterion 3 — MAIN CLAUSE PROVEN

`regions_prev` (352 bytes, 11 elements) serialises into the project `statePayloads`.
Decoded the saved payload and compared field-by-field against a live
`capture_data_port` after a real save -> load cycle: **all 10 authored elements are
byte-identical**. Element 9 changed, correctly — that is the transient firing-flash
record, not authored state. `sentinel_viewport state` reports non-zero captured bytes.

The buffer-layout guard also validated: the header, flash, and Hz-publication records
all carry `enabled = 0`, so nothing scanning the buffer can mistake them for regions.

### Criterion 4 — MET

A still cannot distinguish "flashing" from "always bright", so the flash was measured
over time. First attempt produced 16 byte-identical frames — the corpus WAV had
finished playing and the console was frozen; the test was measuring a dead image.
Re-run during active playback (frame-to-frame diff ~65/255), tracking a FIXED region
border row rather than re-picking the brightest row each frame:

    row 130: 185.5 218.2 255.0 202.8 255.0 197.2 234.6 183.3 218.2 255.0 199.0 ...
             min 160.1  max 255.0  range 94.9 (37% of full range)

Saturating at each fire and decaying between, which is the `exp(-dt/tau)` behaviour.

### Criterion 6 — MET

`./tools/module-ui.ps1 validate modules/pulse2_console` -> `OK  Pulse2 / Console`.

Criterion 1 re-checked across panel extents. Note: `resolution_mode: follow_panel`
means the extent is dock-driven — writing `resolution_width` is ignored, so the exact
640x360 / 1600x900 figures are not directly settable. Reached them by resizing the
Sentinel window and toggling dock panels:

| panel extent | hats HF/LF | four HF/LF |
| --- | --- | --- |
| 507x64 | 2.76 | 0.84 |
| 719x414 | 4.67 | 0.86 |
| 719x744 | 4.90 | 0.81 |

The contrast direction holds at every extent.

### Palette — changed at user request

The user reviewed the monochrome build at this checkpoint and asked for a darker base
running through a colour spectrum so instruments separate. Implemented as `p2_ramp`
(near-black -> indigo -> magenta -> orange -> pale yellow) behind a continuous
`disp_hue` control, so the authored greyscale is `disp_hue = 0` rather than deleted.
Region chrome moved from the warm accent to a cool edge colour, because an orange
border on the ramp's warm upper range vanishes exactly where content is loudest.

This DEVIATES from CLAUDE.md and from the phase doc, which both specify the monochrome
instrument look and explicitly rule out a Magma/Inferno ramp. Recorded as a user
decision, not drift. Their reasoning is sound: hue separates a kick from a hat at
equal brightness, where greyscale collapses everything loud onto the same white.

## Still open

- **Criterion 2 — mechanism confirmed, one clause outstanding.** The user's real drag
  delivered **1315** events (`dbg_events`), and they observed detection responding
  inside the drawn band. Not yet captured: a vision check asserting a visible region
  box at the dragged coordinates. The console was recreated after their drag, which
  reset the latch and the regions to seeds.
- **Criterion 3 — undo of a region drag.** Needs a drag to undo.
- **Criterion 5 — implemented and visible, one legibility caveat.** Flux and threshold
  render per region. But the detector's trace ring is 256 hops while the display now
  shows 768, so the mini-trace only covers the most recent ~1.4 s of a 4.1 s window
  and reads as if it starts partway across. Alignment was kept correct in preference
  to stretching the trace, since a stretched trace would put a spike under the wrong
  spectrogram column. Widening the ring means growing the analyzer's `pstate` buffer,
  which is scored code — deferred rather than risked here.

## Next

Two clauses need one more human drag. Then 2C3 lateral inhibition, which targets the
open 2C1 snare precision deficit (0.31-0.34).
