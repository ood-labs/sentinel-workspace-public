# Audio In — Field Report from First Real Use

**Build:** Sentinel 0.5.48
**Date:** 2026-07-24
**Context:** Built `cryo_pulse`, a from-scratch beat/onset detector, as part of the CRYOGRAM example. No stock audio Modules existed in this workspace, so everything below comes from implementing spectral-flux onset detection, adaptive thresholding, and autocorrelation tempo tracking directly against the published data ports.

This is a usage report, not a bug list. Severity ratings reflect impact on someone building audio-reactive work, not code correctness.

---

## 1. What was built

`cryo_pulse` consumes `Mel Bands` and publishes 15 control outputs:

| Group | Outputs |
| --- | --- |
| Envelopes | `kick`, `snare`, `hihat` |
| Counters | `kick_count`, `snare_count`, `hihat_count`, `onset_count` |
| Tempo | `bpm`, `beat_phase`, `beat_pulse`, `tempo_conf` |
| Energy | `bass`, `mid`, `treble`, `level` |

Algorithm: per-hop log compression of 138 mel bands → half-wave-rectified spectral flux in three band lanes → per-lane adaptive threshold (EMA of flux + k·EMA of deviation) → refractory gating → autocorrelation over a self-maintained 512-hop history → beat-phase PLL corrected by kick onsets.

**It works.** It tracks tempo on real material and fires cleanly separated lanes. Everything below is about what made getting there harder than it needed to be.

---

## 2. Verified surface

Facts confirmed directly via `get_data_schemas` / `info` this session.

| Port | elementCount | elementSize | Structure |
| --- | --- | --- | --- |
| `PCM` | 16385 | 48 | **1 header + 16384 stereo frames** |
| `Spectrum` | 65536 | 40 | **64 hops × 1024 bins, no header** |
| `Mel Bands` | 8832 | 40 | **64 hops × 138 bands, no header** |

- Every record carries `hop_index`, `sample_position`, `generation_counter`, `qpc_ticks_lo/hi`, `sample_rate`, `fft_size`, `hop_size`, `value_count`.
- `generation_counter` advances ~187/s at 48 kHz with hop 256, matching `sample_rate / hop_size`.
- `level` and `peak` are ordinary scalar control outputs.
- `statusMessage` carries endpoint name, `(Streaming)`, `migrations N`, `gap-fill N`.
- `rescan_devices` correctly migrated a stale binding to the live default endpoint (`migrations 0 → 1`).

---

## 3. Defects found

### D1 — `_Data0[0].generation_counter` is wrong for Spectrum and Mel Bands — **HIGH**

`knowledge/audio-reactivity.md` documents the consumer loop as:

```hlsl
uint latest = _Data0[0].generation_counter;
uint start = AudioRingCatchupStart(read_cursor, latest, AUDIO_HOP_RING_CAPACITY);
```

This is correct for `PCM`, which has a header element. It is **wrong for `Spectrum` and `Mel Bands`**, which have no header — element 0 is ring slot 0, band 0. Its generation only changes when the ring wraps back to slot 0, i.e. **once every 64 hops (~341 ms)**.

**Symptom:** the detector idles, then swallows 64 hops in a single burst, roughly 3× per second. Visually the whole analysis appears to run at ~3 fps while the module is provably cooking at 60 Hz. Onset timing quantises to 341 ms buckets. Tempo estimates still converge, so the result looks *plausible* — this is a silent correctness bug, not a crash.

**Workaround now in `cryo_pulse`:**

```hlsl
uint slots = min((uint)_Data0_Count / max(vcount, 1u), 64u);
uint latest = 0u;
for (uint s = 0u; s < slots; ++s) {
    uint g = _Data0[s * vcount].generation_counter;
    if (g > latest) latest = g;
}
```

**Requested fix — inject per-data-input uniforms:**

```
_Data0_Generation    // latest published generation
_Data0_ValueCount    // values per hop
_Data0_HopCapacity   // ring depth
```

Preferable to adding headers to Spectrum/Mel because it removes indexing ambiguity entirely, requires no buffer read, and **generalises to every data input, not just audio**.

Related: `cryo_tracker`'s own `Tracks` data output reports `generation: 0`, which silently prevented a downstream `time_dependent: false` pass from ever running. Same root cause — generation is not reliably reachable by consumers. A uniform fixes both.

### D2 — Endpoint loss reports as healthy — **HIGH (show-critical)**

An `audio` node created against `Default loopback` bound to a Bluetooth headset. The headset later disconnected. Sentinel continued reporting:

- `healthy: true`
- `statusMessage: "Headphones (WH-1000XM4) (Streaming), migrations 0, gap-fill 0"`

while the endpoint no longer appeared in `list_audio_devices` at all and delivered only a noise floor (`peak ≈ 0.0196`, ~−44 dBFS). Nothing surfaced the problem. A detector built on it reported **99% tempo confidence on noise**.

**Requested fixes:**
1. Degrade health, or at minimum annotate status, when Device-mode `peak` stays below a floor for N seconds: `Streaming (no signal 12s)`.
2. Make `migrations` and device-lost state queryable as fields, not only as substrings of `statusMessage`.
3. Document plainly: **pin an endpoint by GUID for shows.** "Default loopback" following the OS default means a headset connecting mid-set silently steals capture.

### D3 — Profiler cannot see GPU cost, and lifetime counters invite misdiagnosis — **MEDIUM**

`sentinel_graph profile` reports CPU wall time around `process()` only (the response notes this). For the same single-lane `dispatch:[1,1,1]` reduction pass, observed `wall_time_ms` fluctuated **0.49 → 3.11** across samples with no code change.

Separately, I misdiagnosed a problem by comparing `frames_processed` across nodes — invalid, because nodes created at different times have different lifetime totals. The correct measurement required taking two profiles and differencing against `frame_index`:

```
Δframe_index 1686 · Δcryo_audio 1686 · Δcryo_pulse 1686   → all cooking every frame
```

**Requested fixes:**
1. Per-pass **GPU timestamp** in the profile output.
2. A per-node **cook rate in Hz**, derived over a window. This alone would have prevented the misdiagnosis.
3. Optional `compile_check` lint: warn when a `dispatch:[1,1,1]` pass contains nested loops over structured buffers. This is the documented pattern for event/state reduction, and it is correct — but it is one serial GPU lane, and the cliff is invisible.

### D4 — Parameters do not survive round-trips — **MEDIUM, needs confirmation**

Two instances, not deeply investigated:
- Tuned `features` corner params (`corner_quality 0.48`, `corner_min_distance 17`) reverted to defaults on **project load**, silently restoring a 9.3 ms hotspot.
- `cryo_relief` internal-camera pose reset to zeros on **force_reload**.

Unclear whether either is expected. Both are easy to miss because the graph still renders.

---

## 4. Capability assessment

**Is the current surface enough?** For a large class of work, yes. For serious music-information retrieval, there are two real gaps.

### Sufficient today

| Task | Verdict |
| --- | --- |
| Band-limited energy envelopes | Fully supported |
| Spectral-flux onset detection | Fully supported; Mel Bands is well suited |
| Kick vs hi-hat separation | Good — frequency separation does most of the work |
| Amplitude reactivity | `level` / `peak` are enough on their own |
| Tempo (BPM) estimation | Achievable, but requires self-maintained history (below) |
| Beat phase / PLL | Achievable |

### Gap 1 — 64-hop retention (~341 ms) forces every module to rebuild history — **biggest structural limit**

Tempo, beat tracking, onset-rate statistics, and musical-time normalisation all need seconds of context. 341 ms is not enough for any of them. `cryo_pulse` therefore maintains its own 512-hop ring in a persistent buffer.

That works, but it means:
- every audio module reimplements ring maintenance;
- each cook carries a serial copy of the entire state buffer;
- a stall longer than 341 ms silently drops hops with no signal to the consumer.

**Ask:** configurable retention (e.g. up to 1024 hops ≈ 5.5 s), or an engine-side longer-history port. Even doubling to 128 hops would help; 512 would remove the need for consumer-side rings in most cases.

### Gap 2 — magnitude only, no phase — **biggest algorithmic limit**

`Spectrum` publishes `magnitude`. Without phase (or real/imag), we are restricted to energy-increase detection. Complex-domain onset detection — which uses phase deviation to predict where a bin *should* be and flags departures — is the standard improvement over pure spectral flux. It substantially outperforms magnitude flux on:

- soft and legato onsets,
- pitched/tonal note onsets (bass lines, stabs, melodic material),
- distinguishing a genuine onset from an amplitude swell.

Everything built so far over-triggers on swells and under-detects tonal onsets, and that is a direct consequence of having magnitude only.

**Ask:** optionally publish phase or real/imag alongside magnitude on `Spectrum`. This is the single highest-value algorithmic upgrade available.

### Gap 3 — stereo handling undocumented — **needs verification, not yet a defect**

`PCM` carries `left` and `right`. `Spectrum` and `Mel Bands` expose a single `magnitude` / `energy` per bin, and the docs do not state how channels are combined (sum? average? left only? mid?).

This matters: mid/side separation is genuinely useful for drum detection — kick and snare are typically centred, hats and reverb are wide. Side-channel analysis is a cheap, large win for isolating percussion from a dense mix.

**Ask:** document the current behaviour; consider exposing a channel mode (`Mono`, `Mid`, `Side`, `L`, `R`).

### Gap 4 — no harmonic/percussive separation

HPSS (median filtering across time vs across frequency on the spectrogram) is standard preprocessing for drum detection and would sharply improve snare detection specifically. Implementable in a Module — but only with a 2D window, which returns to Gap 1.

### Honest note on snare

Kick and hi-hat are largely solved by band splitting. **Snare is not**, and no amount of band tuning fixes it: snare is broadband and overlaps everything. Meaningful snare detection needs either phase-based onset detection (Gap 2), percussive separation (Gap 4), or mid/side (Gap 3). This is currently the weakest lane, and it is an information limit rather than a tuning problem.

---

## 5. Proposed experiments

Ranked by value. None require engine changes; all sharpen the asks above.

| # | Experiment | Method | Settles |
| --- | --- | --- | --- |
| **E1** | Stereo semantics | Play a hard-panned tone; compare `Spectrum`/`Mel` against `PCM` left/right | Gap 3 — what channel combination is actually published |
| **E2** | End-to-end latency | Click track → `onset_count` increment → visible change, using record `qpc_ticks` | Whether audio→visual latency is show-acceptable, and where it accrues |
| **E3** | Generation semantics on all three ports | Log element-0 vs max-across-slots generation for PCM/Spectrum/Mel | Confirms D1 scope and whether PCM's header is the only exception |
| **E4** | Ring-wrap under stall | Force a >341 ms frame; check `gap-fill` and whether hops are lost silently | Gap 1 severity; whether consumers can even detect loss |
| **E5** | Detector accuracy vs ground truth | Needs a drum-loop WAV with known BPM and hit positions; measure per-lane precision/recall and BPM error | Turns detector tuning from taste into measurement |
| **E6** | Mel vs linear Spectrum for kick | Run the same flux detector on low mel bands vs low linear bins | Whether 138 mel bands have enough low-end resolution for kick, or `Spectrum` is the better source |
| **E7** | Adaptive-threshold behaviour on silence | Feed digital silence and near-silence | Confirms detectors need a signal-presence gate (see below) |

**Test-asset ask:** the workspace ships `tools/capture_verify/tone_440.wav`. A **drum loop with known BPM and annotated hit positions** would make E5 possible and turn detector development rigorous. This is cheap to produce and high value — currently there is no way to score a detector, only to eyeball it.

---

## 6. Lesson for detector authors (our side, not the engine's)

`cryo_pulse` reported **BPM 96 at 99% confidence while receiving a noise floor.** That is not an engine bug — it is an inherent property of adaptive thresholds. They normalise to whatever is present, so they will *always* find onsets in noise.

Any detector using adaptive thresholding needs a **signal-presence gate** that forces confidence (and ideally BPM) to zero below a level floor. This belongs in the detector, and should be called out in the authoring guidance so the next person doesn't ship a confidently-wrong node.

---

## 7. Summary of requests

**Engine, ranked:**

1. Inject `_DataN_Generation` / `_DataN_ValueCount` / `_DataN_HopCapacity` uniforms — fixes D1 and the `generation: 0` dirty-flag problem in one move.
2. Signal-presence and device-loss reporting on `audio` health (D2).
3. Configurable ring retention, or a longer-history port (Gap 1).
4. Publish phase / real+imag on `Spectrum` (Gap 2).
5. Per-pass GPU timing and per-node cook-rate Hz in `profile` (D3).
6. Document (and ideally expose) stereo handling for Spectrum/Mel (Gap 3).
7. Confirm/fix parameter persistence across load and force_reload (D4).

**Docs:**

- Correct the consumer-loop example in `knowledge/audio-reactivity.md` — it is currently wrong for the two ports most likely to be used.
- State the header/no-header difference explicitly in the port table.
- Recommend GUID-pinned endpoints for shows.
- Add the signal-gate guidance for adaptive detectors.

**Assets:**

- An annotated drum-loop test WAV.
