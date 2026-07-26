# Audio Analysis v2 — Implementation Plan

Derived from `docs/research_results/Production Grade GPU Audio Analysis...html` and the
first-use findings in `projects/cryogram/AUDIO-REACTIVITY-FIELD-REPORT.md`.

Target: a reusable analysis Module (`pulse2`) that every future audio-reactive
project consumes, replacing `modules/cryo_pulse`.

---

## The three findings that change the design

1. **Adaptive spectral whitening removes the threshold problem entirely.**
   Per-bin running peak `P[n,k] = max(r·P[n-1,k], |X[n,k]|)` with `r ≈ 0.992`,
   then `Y = |X| / max(P, 1e-4)`. Every bin is normalised to 0..1, so a quiet
   hi-hat competes on equal terms with a loud kick. This is the direct fix for
   the defect where one global `threshold_floor` starved the hat lane and
   over-triggered the kick lane simultaneously — there is no longer anything to
   starve.

2. **Snare needs features, not a better band.** No frequency region separates a
   snare from a coincident kick. The fix is a 4-feature vector per region —
   whitened flux, spectral centroid, spectral flatness, temporal decay — and a
   weighted decision. Snare reads high flatness (noise-like), high centroid,
   fast decay; kick reads the inverse. This discriminates even when both land on
   the same frame.

3. **Comb Filter Matrix beats autocorrelation, and gives phase for free.**
   `X(τ, θ)` over tempo period and phase offset. The argmax gives tempo *and*
   current phase in one structure. Autocorrelation measures lag similarity and
   is prone to octave leaps; comb resonators reinforce genuine periodic pulse
   trains. Maps to a 2D thread grid — ideal for us.

## Decisions taken

| Decision | Value | Reasoning |
| --- | --- | --- |
| `fft_size` | **4096** | 11.7 Hz/bin resolves kick fundamental (40–80 Hz) across 3–4 bins vs <15 Mel bands for the whole 40–250 Hz range. Costs the 12–24 kHz air band, but hat fundamentals sit 5–10 kHz and snare crispness 3–7 kHz, both retained. **Testable claim — verify in Phase 0.** |
| Primary input | **Linear `Spectrum`** (1024 bins) | Surgical isolation and the click-to-place UI both need uniform fine bins. |
| Secondary input | **`Mel Bands`** | Broadband onset-strength aggregation for the tempo OSS. |
| Onset function | **Adaptive-whitened SuperFlux** | `D[n,k] = max(0, Y[n,k] − max_{m∈[−2,2]} Y[n−1,k+m])` |
| Peak picking | Moving median + mean, local-max, refractory | 1-hop (5.3 ms) lookahead removes ~80% of double triggers; imperceptible. |
| Onset history | **800 hops (~4.26 s)** | Two bars down to 30 BPM; tracks a pitch bend within 1–2 bars. |
| Tempo | **Comb Filter Matrix** + log-Gaussian prior (σ=0.8 oct, peak 120) + harmonic suppression | |
| Beat phase | **Dual-loop PLL**, `μ_phase=0.15`, `μ_tempo=0.02` | Spurious fills barely move it; real shifts lock within two bars. |
| Confidence | Peak-to-average ratio of comb output; **free-wheel hold** below threshold | Principled replacement for the signal gate hack. |

Budget: ~0.21 ms/frame across 5 passes. Comfortable.

## Phase order — deliberately NOT the research's order

The research puts the test harness last. **That is the one thing I will not
repeat.** Every failure in the CRYOGRAM session came from tuning by eye with no
way to tell whether a change helped. Scoring comes first.

### Phase 0 — Scoring harness and synthetic corpus (BLOCKING)

- Generate programmed drum patterns to WAV with exact annotation sidecars
  (Python, synthesised kick/snare/hat — no VSTs needed for a first pass).
  Cover: 4-on-floor, breakbeat, syncopated, sparse, dense, tempo ramp, quiet
  intro into loud drop.
- Deterministic playback through Audio In File mode.
- Dump detector buffers, score onset F1 (±25 ms window) and BPM error.
- **Also settles the `fft_size` 4096-vs-2048 claim empirically.**
- Exit: a single command prints F1 per lane and BPM error per track.

### Phase 1 — `pulse2` core detector

Whitening → SuperFlux → median/mean peak-picking with 1-hop lookahead.
Keep fixed lanes initially so it is a drop-in comparison against `cryo_pulse`.
Exit: measurably higher F1 than `cryo_pulse` on the Phase 0 corpus.

### Phase 2 — Region masks and the spectrogram UI

- 2D regions on the linear spectrum; rectangle, Gaussian, comb-harmonic, freeform.
- Canvas panel: log-frequency rebinning, per-bin peak equalisation, `γ=0.45`
  power-law compression. Click-drag to place, assign to a control output.
- Per-region live flux trace + threshold overlay + trigger flash.
- Lateral inhibition so one transient cannot fire every lane.
- Exit: place a kick and hat region by eye in under a minute; both score well.

### Phase 3 — Multi-feature classifier (the snare fix)

Centroid, flatness, decay added per region; weighted decision.
Exit: snare F1 materially up on the dense-mix corpus tracks.

### Phase 4 — Comb Filter Matrix tempo + dual-loop PLL

Replaces autocorrelation. Adds tempo prior, harmonic suppression, honest
confidence, free-wheel hold.
Exit: correct metrical level on ≥90% of corpus; survives a tempo ramp.

### Phase 5 — HPSS, only if still needed

2D median filtering (9 hops along time, 17 bins along frequency) to strip
sustained bass from percussive transients. Expensive; defer until Phase 3
proves insufficient.

## Engine asks (from the research, ranked)

1. **Complex FFT output** (real/imag or phase) — unlocks complex-domain ODFs.
   Magnitude-only reaches ~92% of complex-domain F1 on percussion, so this is
   valuable but not blocking for drums.
2. **Longer ring** — 64 hops → 1024 hops (~5.5 s). Would remove consumer-side
   ring maintenance entirely.
3. **Multi-resolution dual STFT** — 1024 for time, 4096 for frequency.
4. **Mid/side or un-summed L/R** — isolates centre-panned kick/snare from
   hard-panned material. Currently `0.5·(L+R)` only.

## Open risks

- The CFM update reads `X` at previous phase positions; needs careful ping-pong
  or it will read partially-updated state.
- HPSS median filtering is a selection network per bin per hop — cost unverified.
- All constants (`r`, `μ_phase`, `α_comb`, `γ`) are literature starting points,
  not measurements. Phase 0 exists to validate them.
