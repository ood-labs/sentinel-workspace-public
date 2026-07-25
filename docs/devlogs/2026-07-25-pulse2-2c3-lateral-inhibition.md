---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2C3
status: blocked
approval: pending
summary: "2C3 - three attempts fail; snare FP proven to be one-per-kick timbre leakage, belongs to 2D"
---

## Outcome

**2C3 does not pass, and the evidence says its mechanism cannot make it pass.**
Three designs were implemented and measured on the tuning set. All three failed.

The analyzer is left at `inhibit_gain = 0.0`, verified bit-identical to the
scored 2C1 detector (8 tuning patterns x 3 lanes, every delta exactly 0), so
nothing downstream is disturbed and 2D can start from a clean baseline.

Recommendation: let **2D** carry the snare deficit. Reasoning at the end.

## A scoring error of mine, cleared first

The gate initially "failed" with kick/hat collapsing. Not a code regression:
`score_detector.py --lane-map` defaults to `lane_map.json`, which targets the OLD
`pulse_baseline` detector on Mel Bands, while the committed 2C1 table came from
`lane_map_pulse2.json` (Spectrum). I scored the wrong pipeline against the right
table.

Re-run correctly, 2C1 reproduces exactly — every per-lane delta `+0.000` across
11 patterns, aggregate 0.7972, gate PASS. Two guards now prevent a repeat:
`sweep_inhibit.py` pins the lane map as a module constant, and its summariser
asserts `d["detector"] == "pulse2_analyzer"` from the saved table itself.

## Attempt 1 - instantaneous inhibition (the phase doc's formula)

`O'_i = max(0, O_i - g * max_{j!=i} O_j)`. Tuning-set snare FP at
g = 0 / 0.15 / 0.3 / 0.5: **284 / 288 / 285 / 279**. The target lane did not move.

`diag_inhibit.py` on `hats_under_loud_kick_150` (zero true snares, so every snare
firing is leakage by construction) shows why. At the 43 hops where the snare
falsely fires: snare flux 0.1955, threshold 0.0805, **kick flux at the same hop
0.0021**. Gain needed: **8.805**. Suppressible at any `g <= 1`: **0%**.

The rival is silent at the instant of the false positive. Widening the window
finds it: median kick flux within +/-3 hops 0.0021, within **+/-8 hops 0.3222**,
rival louder than snare on **95.45%** of fires. Distance to the nearest active
kick hop: median **8 hops (43 ms), p25 = p75 = 8** — a fixed lag.

So the interference is the kick's **decay** entering 200-2400 Hz ~43 ms after its
transient. Flux spikes at transients, so a same-hop rival term is blind to it by
construction. The phase doc's instantaneous formula cannot address this signal.

Fixed alongside: the moving-median background had been routed through the
inhibited signal, so `thr = alpha + lambda*median(O')` sagged with the signal and
the subtraction cancelled out of `(o - thr)`. It now reads raw flux, keeping thr
exactly the 2C1 threshold.

## Attempt 2 - symmetric forward masking

`R_i[n] = max_d exp(-d/tau) * max_{j!=i} O_j[n-d]`, stateless over the Lane ring.

| gain, tau | kick recall | snare FP | hat recall | aggregate |
| --- | --- | --- | --- | --- |
| 0.0, 6 | 0.948 | 284 | 0.958 | **0.7970** |
| 0.6, 12 | 0.440 | 258 | 0.867 | 0.706 |
| 0.9, 12 | 0.078 | 195 | 0.558 | 0.507 |
| 1.0, 16 | 0.063 | 174 (-39%) | 0.492 | 0.451 |

Snare FP finally moves, but the kick lane is destroyed getting there. Cause: hat
flux p99 **1.0359** vs kick **0.4984**, and hats at 150 BPM fire continuously, so
at tau=12 the hat envelope never decays and lays a permanent masking floor over
the sparse kick lane.

## Attempt 3 - directional masking (low frequency masks high only)

Rivals restricted to `j < lane`, so lane 0 is unmaskable by construction.

| gain, tau | kick recall | snare FP | snare recall | hat recall | aggregate |
| --- | --- | --- | --- | --- | --- |
| 0.0, 6 | 0.948 | 284 | 0.993 | 0.958 | **0.7970** |
| 0.5, 12 | **0.948** | 260 | 0.894 | 0.885 | 0.790 |
| 0.7, 12 | **0.948** | 251 | 0.894 | 0.831 | 0.792 |
| 0.9, 12 | **0.948** | 249 (-12%) | 0.894 | 0.559 | 0.701 |

The kick guarantee holds exactly — fp=14, tp=254, recall 0.948 at every gain.
That half of the design works as intended.

The snare does not: FP falls 12% against a 40% target while snare recall drops
0.993 -> 0.894, a 0.099 loss against a 0.03 allowance. Fails both halves.

## The finding that ends the sub-phase - ONE FALSE POSITIVE PER KICK

| pattern | kick TP | hat TP | snare FP |
| --- | --- | --- | --- |
| `hats_only_150` | 0 | 96 | **0** |
| `breakbeat_170` | 27 | 109 | **27** |
| `hats_under_loud_kick_150` | 48 | 193 | **48** |
| `four_on_floor_128` | 41 | 82 | 40 |
| `quiet_intro_drop_128` | 41 | 82 | 32 |
| `sparse_90` | 7 | 14 | 16 |
| `dense_140` | 56 | 180 | 71 |
| `syncopated_funk_105` | 34 | 67 | 50 |

`hats_only_150`: 96 hi-hats, no kick, **zero** snare false positives. This
refutes hat-to-snare leakage — and with it the frequency-overlap argument I used
to justify attempt 3, which assumed hats might leak down into 200-2400 Hz.

Every kick yields almost exactly one spurious snare (27->27, 48->48, 41->40).
`dense_140` and `syncopated_funk_105` exceed 1:1, so a secondary source exists,
most likely snare double-triggering (`breakbeat_170`: 42 real snares, 41 TP,
27 FP).

**Why masking cannot finish the job.** Suppressing the kick-induced peak does not
remove the detection, it moves it: the leakage is a broad bump across the kick's
decay, `thr` is fixed, and whichever hop still clears the bar fires instead while
the ~10-hop refractory admits exactly one. Consistent with the measurement — FP
fell by 35 while 15 REAL snares were suppressed, trading true for false at ~1:2.

## Conclusion - this is classification, not competition

The kick's decay is a genuine onset inside the snare's band. It is not weaker
than a real snare and not simultaneous with anything, so no threshold, gain, or
masking window separates them: they differ in **timbre**, not level or timing. A
kick decay is low-centroid, smooth, tonal; a snare is high-centroid, noisy, high
spectral flatness.

That is precisely sub-phase **2D**, whose criterion already targets this exact
number (snare F1 >= 0.75 on `kick_snare_coincident_124`, +0.15 over 2C1). 2D
should carry the deficit.

## Criterion status

**Criterion 1 was never evaluated.** It measures on `kick_snare_coincident_124`,
a held-out pattern; no candidate survived the tuning set, so no held-out
evaluation was spent. Targets remain fixed and unused: FP 35 -> <= 21, recall
floors kick >= 0.899, snare >= 0.946, hat >= 0.922.

Neither held-out pattern influenced any choice recorded here.

## Deviations needing sign-off

1. The phase doc specifies instantaneous `O_i - sum beta_ji * O_j`. Measurement
   shows that formula is structurally unable to address the deficit it was
   written for. The temporal and directional generalizations are departures.
2. The code ships **disabled by default** (`inhibit_gain = 0.0`, proven no-op).
   It is retained because the kick-protection guarantee and the diagnostics are
   worth keeping, not because it is doing useful work today.
3. Recommending that 2C3's deficit be carried by 2D is a plan change.

## Files

- `modules/pulse2_analyzer/pick.hlsl` — directional forward-masking `rival_env()`,
  raw-flux median background, all three attempts documented in comments
- `modules/pulse2_analyzer/manifest.yaml` — `inhibit_tau_hops` (hops, not seconds)
- `tools/audio_test/diag_inhibit.py` — the H1/H3 diagnostic
- `tools/audio_test/sweep_inhibit.py` — (gain, tau) grid, held-out + lane-map guards
- `tools/audio_test/diag_trace.py` — repaired: was reading the trace ring at the
  old stride 16 / 64 hops against the current stride-3 / 256-slot layout
- `tools/audio_test/scores/2C3_baseline_notes.md` — baselines and all three attempts

## Next

Human decision on carrying the snare deficit into 2D.
