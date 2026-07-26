# Pulse2 — audio onset and beat analysis

A drum-onset detector and beat clock built on Sentinel's `audio` node, scored
against a frozen synthetic corpus rather than by eye. Open
`projects/pulse2/pulse2.sentinel`.

## Build requirement

Requires a Sentinel build whose `list_types` includes the `audio` pipeline type.
Published builds at or below 0.5.48 omit it. Check before loading:

```
sentinel_pipeline action=list_types
```

## What is in the graph

| Node | Role |
| --- | --- |
| `pulse2_audio` | Audio In. Ships in File mode on a corpus WAV so the project is reproducible; switch `source_mode` to Device for live use. |
| `pulse2_analyzer` | The detector. Whitening, region masks, flux, features, classifier, peak picking, comb matrix, tempo, PLL beat clock. |
| `pulse2_console` | Spectrogram and region console. |
| `pulse2_ringproof` | Ring-buffer catch-up proof. |
| `pulse_baseline` | The original `cryo_pulse` detector, frozen, for side-by-side comparison. |

`pulse2_analyzer/parameters/gate_level` is driven by an expression from
`pulse2_audio/control_outputs/level`. That is what makes the signal gate work —
if it is ever cleared, the detector will report confident nonsense on silence.

## The `fft_size` coverage trap

**`fft_size` 4096 silently truncates the spectrum to 0–12 kHz.** Nothing in the
data port's metadata reveals it.

The `Spectrum` port always publishes 1024 bins regardless of `fft_size`, and bin
width is exactly `sample_rate / fft_size`. So:

| `fft_size` | bin width | coverage |
| --- | --- | --- |
| 2048 | 23.4 Hz | full 0–24 kHz |
| 4096 | 11.7 Hz | **0–12 kHz only** |

At 4096 the port looks healthy, the bin count is unchanged, and the top octave
of a 48 kHz signal is simply absent — which removes most of the hi-hat energy
this detector's region 2 depends on. Verified by tone: a 440 Hz tone peaks at
bin 37.5 at `fft_size` 4096 and bin 18.8 at 2048.

**This project ships at `fft_size` 2048**, and every committed score table
records the `fft_size` in force. Changing it invalidates the tables.

## Data contract

`pulse2_analyzer` publishes a `Hits` data port, 1024 elements of 4 × `uint`:

```
struct Hit { uint lane_id, onset_serial, hop_index, sample_position; };
```

| Field | Meaning |
| --- | --- |
| `lane_id` | 0 kick, 1 snare, 2 hat, 3 beat |
| `onset_serial` | 1-based, **per lane** |
| `hop_index` | analysis hop the timestamp came from |
| `sample_position` | position in the source stream — **time everything by this** |

Slots 0–511 are the picker's onsets (lanes 0–2); slots 512–1023 are the beat
clock's beats (lane 3). The two rings carry **independent serial sequences**, so
consumers must key records by `(lane_id, onset_serial)`, never by serial alone.

Beats live in a separate ring because two shader passes writing one buffer get
ping-ponged onto separate physical sides and the writes are silently discarded.

Scalar control outputs: `kick` / `snare` / `hihat` and their `_count`s,
`onset_count`, `bpm`, `tempo_conf`, `beat_phase`, `beat_period`, `signal_present`,
plus the beat clock's `pll_phase`, `pll_period`, `bpm_locked`, `beat_conf`,
`free_wheeling`, `beat_count`, `beat_pulse`, `phase_coherence`, and the
diagnostic `drop_signal` / `drop_ring` / `beat_cycles`.

## Measured behaviour

Scored on the frozen corpus `50e89b594f08b41a` at ±25 ms, raw (no latency
compensation). Full table in `tools/audio_test/scores/2E2.json`.

| | mean F1 |
| --- | --- |
| kick | 0.913 |
| snare | 0.782 |
| hat | 0.969 |

Each figure is the mean across the patterns that actually contain that lane;
patterns with no reference hits in a lane are excluded rather than scored as
zero. Averaging all eleven patterns regardless gives 0.921 / 0.731 / 0.969, so
the aggregation rule matters when comparing against other tables.

Tempo is within 2 BPM on every pattern that locks. On a −44 dBFS noise floor and
on digital silence, `tempo_conf` falls to 0.0000, BPM freezes at its last trusted
value, and no counter advances — the failure this project exists to not repeat.
A 30-minute continuous run held F1 to +0.000 and BPM within 127.55–127.77.

**Known limitation.** Beat *continuity* (CMLc/AMLc) is well below target at
0.00–0.78 depending on material. The clock itself is sound — intervals
are regular and no beats are dropped — but beat *placement* carries a
pattern-dependent residual from the comb's phase argmax. Use `bpm` /
`beat_period` / `beat_pulse` for tempo-locked motion; do not rely on individual
beat timestamps being sample-accurate.

Three patterns do not resolve their tempo and are known-off: `sparse_90`,
`hats_only_150` (100 byte-identical hats at exactly 9600-sample spacing — no
phase information exists in it), and `halftime_shuffle_88`.

## Re-scoring

```
cd tools/audio_test
python score_detector.py --baseline scores/2E2.json \
    --lane-map lane_map_pulse2.json --detector pulse2_analyzer
```

The corpus is hash-frozen; the scorer refuses to run if any WAV has drifted.
`halftime_shuffle_88` and `kick_snare_coincident_124` are held out and must never
be tuned against.
