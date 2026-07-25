# 2C3 baselines (computed from scores/2C1.json, before any tuning)

All figures below are the `inhibit_gain = 0.0` state, which was proven
bit-identical to the committed 2C1 table (every per-lane delta +0.000 across 11
patterns, aggregate 0.7972). So the 2C3 code path is a true no-op when disabled.

## Tuning set (8 patterns; held-out excluded)

| lane | fp | tp | fn | recall |
| --- | --- | --- | --- | --- |
| kick | 14 | 254 | 14 | 0.948 |
| snare | **284** | 141 | 1 | 0.993 |
| hat | 32 | 823 | 36 | 0.958 |

mean aggregate F1 = 0.7970

The snare lane emits 425 detections for 142 true snares. Recall is essentially
perfect; precision is the whole deficit. A kick's broadband click deposits real
energy in 200-2400 Hz, so the snare region reduces a genuine onset that belongs
to another instrument. No per-lane threshold fixes that — hence competition.

## Held-out (NOT tuned against; evaluation only)

`kick_snare_coincident_124` - the 2C3 pass criterion pattern:

| lane | fp | tp | fn | recall |
| --- | --- | --- | --- | --- |
| kick | 0 | 39 | 3 | 0.929 |
| snare | **35** | 40 | 1 | 0.976 |
| hat | 0 | 79 | 4 | 0.952 |

Total cross-lane FP = 35, entirely in the snare lane.

**Criterion 1 targets, fixed before measuring:**
- FP must fall >= 40%: 35 -> **<= 21**
- recall must drop < 0.03 per lane: kick >= 0.899, snare >= 0.946, hat >= 0.922

`halftime_shuffle_88` (second held-out): 35 FP total (kick 7, snare 28, hat 0).

**Predicted worst case, stated before measuring:** the inhibition is symmetric
and instantaneous, so a genuinely simultaneous kick+snare is where it should do
the most damage — snare recall on `kick_snare_coincident_124` is the number most
at risk. That pattern is held out precisely so it cannot pick the gain.

## First attempt FAILED, and the diagnosis changed the design

Instantaneous inhibition did essentially nothing to the target lane. Tuning-set
snare FP across g = 0 / 0.15 / 0.3 / 0.5: **284 / 288 / 285 / 279**. Kick FP fell
14 -> 7 and hat FP 32 -> 17, which is a real but incidental gain.

`diag_inhibit.py` on `hats_under_loud_kick_150` (zero true snares, so every
snare firing is leakage by construction) explains it. At the 43 hops where the
snare lane falsely fires:

| quantity | median |
| --- | --- |
| snare flux | 0.1955 |
| snare threshold | 0.0805 |
| **kick flux, same hop** | **0.0021** |
| max rival, same hop | 0.0131 |
| gain needed to suppress | **8.805** |

Suppressible at any `g <= 1`: **0%**. The rival is silent at the moment of the
false positive, so no amount of same-hop gain can work.

The window scan finds the energy:

| window | median kick flux | rival/snare | rival > snare |
| --- | --- | --- | --- |
| +/-0..3 hops | 0.0021 | 0.011 | 0% |
| +/-5 hops | 0.0037 | 0.019 | 0% |
| **+/-8 hops (43 ms)** | **0.3222** | **1.648** | **95.45%** |
| +/-12 hops | 0.4984 | 2.549 | 95.45% |

Distance from each snare FP to the nearest active kick hop: median **8 hops
(43 ms), p25 = p75 = 8**. A fixed lag, not jitter.

So the interference is the kick's DECAY arriving in 200-2400 Hz ~43 ms after its
own transient. Flux spikes at the transient, so a same-hop rival term is blind
to it by construction. Two consequences:

1. The mechanism became **forward masking** over a decaying window
   `R_i[n] = max_d exp(-d/tau) * max_{j!=i} O_j[n-d]`, which is also what real
   hearing does (a transient masks quieter events for ~100 ms after it).
2. The moving-median background now reads **raw** flux. Routing it through the
   inhibited signal made `thr = alpha + lambda*median(O')` sag with the signal,
   so the subtraction cancelled out of `(o - thr)`. The threshold is now exactly
   the 2C1 threshold and the inhibited signal must clear that unchanged bar.

Predicted from the measurements, before running: needed `g*R > 0.115`. With the
kick peak 0.4984 eight hops back, `tau=6` gives `R~0.132` (needs g>0.87) and
`tau=12` gives `R~0.256` (needs g>0.45). tau is the dominant knob, so the second
sweep is a (gain, tau) grid rather than gain alone.

## Second attempt ALSO FAILED - symmetric masking crushes the sparse lanes

| gain, tau | kick recall | snare FP | hat recall | aggregate F1 |
| --- | --- | --- | --- | --- |
| 0.0, 6 | 0.948 | 284 | 0.958 | **0.7970** (exact 2C1) |
| 0.6, 12 | 0.440 | 258 (-9%) | 0.867 | 0.706 |
| 0.9, 12 | 0.078 | 195 (-31%) | 0.558 | 0.507 |
| 1.0, 16 | 0.063 | 174 (-39%) | 0.492 | 0.451 |

Forward masking does reach the target — snare FP finally moves (284 -> 174) —
but it destroys the kick lane to get there. Cause is already in the diagnostic
above: hat flux p99 is **1.0359** against kick **0.4984**, and hats at 150 BPM
fire continuously. With tau=12 the hat envelope never decays between hats, so a
SYMMETRIC rival term lays a permanent masking floor over the sparse kick lane.

The g=0 row is a genuine no-op, verified per-pattern (8 patterns x 3 lanes, all
deltas exactly 0), so the raw-median change did not disturb 2C1.

**Conclusion: symmetric competition is the wrong model here.** The leak that was
actually measured is DIRECTIONAL — a kick's decay rises into the snare band. The
reverse cannot happen: hats live at 2400-20000 Hz and have no energy at all in
the kick's 25-200 Hz region, so a hat physically cannot mask a kick. Masking
should therefore run low-frequency -> high-frequency only:

  kick  (region 0): no rivals -> never inhibited, recall preserved by construction
  snare (region 1): rival = kick          <- the measured 43 ms leak
  hat   (region 2): rivals = kick, snare

## Third attempt - directional masking. Kick protected, snare still not fixed

| gain, tau | kick recall | snare FP | snare recall | hat recall | aggregate |
| --- | --- | --- | --- | --- | --- |
| 0.0, 6 | 0.948 | 284 | 0.993 | 0.958 | **0.7970** |
| 0.5, 12 | **0.948** | 260 | 0.894 | 0.885 | 0.790 |
| 0.7, 12 | **0.948** | 251 | 0.894 | 0.831 | 0.792 |
| 0.9, 12 | **0.948** | 249 (-12%) | 0.894 | 0.559 | 0.701 |

The kick guarantee holds exactly: fp=14, tp=254, recall 0.948 at EVERY gain,
identical to baseline, because lane 0 has no rivals by construction rather than
by tuning. That part of the design works.

The snare does not. FP falls only 12% against a 40% target, while snare recall
drops 0.993 -> 0.894 — a 0.099 loss against a 0.03 allowance. Fails both halves.

## Where the false positives actually are - ONE PER KICK

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

`hats_only_150` has 96 hi-hats, no kick, and **zero** snare false positives.
That refutes hat-to-snare leakage outright — and refutes the frequency-overlap
reasoning used to justify the directional design, which assumed hats might leak
down into 200-2400 Hz. They do not, at least not enough to fire.

Meanwhile every kick yields almost exactly one spurious snare: 27 -> 27,
48 -> 48, 41 -> 40. `dense_140` and `syncopated_funk_105` run above 1:1, so a
secondary source exists as well (most likely snare double-triggering: e.g.
`breakbeat_170` has 42 real snares, 41 TP and 27 FP).

## Why masking cannot finish the job

Suppressing the kick-induced peak does not remove the detection, it MOVES it.
The leakage is a broad bump in the kick's decay, and `thr` is now fixed, so
whichever hop in that bump still clears the bar fires instead — and the ~10-hop
refractory means only one of them ever does. That is consistent with what was
observed: FP fell by 35 while 15 REAL snares were suppressed. The mechanism is
trading true positives for false ones at roughly 1:2.

## Conclusion: this is a classification problem, not a competition problem

The kick's decay is a genuine onset in the snare's band. It is not weaker than a
real snare and it is not simultaneous with anything — so no threshold, no gain,
and no masking window separates the two, because they differ in TIMBRE, not in
level or timing. A kick decay is low-centroid, smooth and tonal; a snare is
high-centroid, noisy, high spectral flatness.

That is exactly sub-phase **2D**, whose pass criterion already targets this
number (snare F1 >= 0.75 on `kick_snare_coincident_124`, +0.15 over 2C1). The
right move is to let 2D's multi-feature classifier carry the snare deficit
rather than force it through a mechanism that measurably cannot address it.

**The 2C3 pass criterion was never evaluated.** It measures on
`kick_snare_coincident_124`, and no candidate survived the tuning set, so no
held-out evaluation was spent. Targets remain fixed and unused: FP 35 -> <= 21,
recall floors kick >= 0.899, snare >= 0.946, hat >= 0.922.
