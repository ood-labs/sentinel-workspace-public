# Engine-side asks for Audio In (D9)

Requests against Sentinel's `audio` node and the Module data-port surface,
re-prioritised against what Phase 2 actually measured rather than what was
guessed at planning time. Every item states the evidence and, where relevant,
which corpus patterns a workaround provably cannot rescue.

Measured on 0.5.49. Corpus `50e89b594f08b41a`; score tables in
`tools/audio_test/scores/`.

---

## 1. Phase-preserving spectral data — HIGH

**Ask.** A complex or phase-bearing output alongside magnitude `Spectrum`, or a
documented phase-vocoder-style port.

**Evidence.** `hats_only_150` is 100 byte-identical hi-hat hits at exactly 9600
samples apart. Magnitude-only analysis cannot resolve its beat phase, and this is
not a tuning shortfall — every candidate phase is equally consistent with the
data, because consecutive hits are bit-identical. It was proven unachievable in
2E1 and formally excluded from that sub-phase's criterion by user decision.

**Provably unrescuable by workaround:** `hats_only_150`.

**Also implicated:** `halftime_shuffle_88` and `sparse_90`, where the onset set
is sparse enough that magnitude flux alone leaves several defensible periods.
Those two are weaker evidence — a better estimator might still reach them.

---

## 2. Spectrum coverage metadata — HIGH, cheap

**Ask.** Publish the covered frequency range (or the truncation factor) in the
`Spectrum` port metadata.

**Evidence.** At `fft_size` 4096 the port covers only 0–12 kHz, while still
publishing its usual 1024 bins. Nothing in the port metadata reveals this. A
consumer that raises `fft_size` for finer resolution silently loses the top
octave — which is most of the hi-hat energy this detector's region 2 depends on.

The trap was found only by sweeping a tone: 440 Hz peaks at bin 37.5 at
`fft_size` 4096 and bin 18.8 at 2048. It costs a consumer a real experiment to
discover something the engine already knows.

This is the cheapest high-value item on the list.

---

## 3. Header record on `Spectrum` and `Mel Bands` — MEDIUM

**Ask.** A per-generation header record, as `PCM` effectively provides.

**Evidence.** Neither ring carries a standalone header, so element zero cannot
serve as a latest-generation source, and consumers must reconstruct chronological
catch-up from `_DataN_Generation` / `_DataN_ValueCount` / `_DataN_HopCapacity`.
This is workable — `pulse2_ringproof` exists to prove the reconstruction — but
every consumer re-implements it, and getting it wrong fails silently rather than
loudly.

---

## 4. Analysis-rate decoupling from cook rate — MEDIUM

**Ask.** Either expose hops-elapsed-this-cook directly, or document that it
varies.

**Evidence.** A control loop written per-cook is implicitly frame-rate
dependent. Phase 2 shipped exactly that bug: the PLL's gains were applied once
per cook, and since a cook covers roughly three hops while a beat spans eighty,
the effective loop gain was ~28x its nominal value and differed between 60 fps
and 30 fps. It presented as a *wrong beat rate* — 28 phase cycles completed where
the period implied 46 — not as a timing warning.

The fix is arithmetic the consumer must know to do. Hops-per-cook is derivable
today from the generation counter, so this is a documentation and ergonomics ask
rather than a capability one.

---

## 5. Two passes writing one buffer — MEDIUM, diagnostics

**Ask.** A lint or runtime warning when two passes declare the same buffer as
output.

**Evidence.** Not audio-specific, but Phase 2 lost significant time to it. Two
passes writing one `persistent` buffer are ping-ponged onto separate physical
sides; the second pass's writes are discarded every cook. It failed **silently
and asymmetrically**: the PLL's state element read back perfectly through both
`Trace` and its control outputs while every write it made to the shared ring and
serial counter vanished. The symptom was a beat count climbing past 23 with not
one beat record in the ring.

`compile_check` already lints structured-buffer size caps and missing compute
targets; this fits the same surface.

---

## 6. File-mode looping — LOW

**Ask.** A loop toggle on `source_mode=File`.

**Evidence.** File mode goes Inactive at EOF, so a long soak must detect the
stall and re-issue `restart_file`. The 30-minute soak in 2E2 ran 85 laps that
way. It works and the restart discontinuity arguably makes the test harsher, so
this is convenience only.

---

## Not asked for

- **Onset detection in the engine.** The whole point of Phase 2 was that a
  detector must be measurable against a frozen corpus. Moving it into the engine
  would remove the ability to score it from the workspace.
- **Higher hop rate.** 187.5 hops/s gives 5.33 ms resolution, comfortably inside
  the ±25 ms scoring tolerance. It is not the limiting factor for anything
  measured here.
