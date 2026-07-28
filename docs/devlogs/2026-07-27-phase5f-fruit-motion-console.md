---
type: devlog
date: 2026-07-27
phase: 5
subphase: 5F
status: complete
approval: pending
summary: "Fruit Motion Console is a responsive sui3 performance panel with all control kinds, group binds, presets, pixels, and runtime behavior proven"
---

# Phase 5F — Fruit Motion Console

## Scope

Ported the Showcase Gallery's bundled `Fruit_LFO` display from the v1 UI
include to the shared sui3 foundation. No later phase and no public promotion
was started.

## Shipped surface

- Responsive full-bleed Canvas with 16 real controls:
  - Master Rate, Mute, Burst, and Motion Bias XY.
  - Speed, amplitude, and waveform for each of four live waveform lanes.
- Four live waveform traces remain attached to prompt position, motion energy,
  camera drift, and pulse.
- Wide mode uses full semantic labels and 21/15/7-pixel typography tiers.
- Compact mode abbreviates the four lanes to `01`–`04` and Mute/Burst to
  `M`/`B` while preserving every hit target.
- The gallery README now documents the console, presets, target resolution, and
  re-import requirement. Curated proof adds `proof/fruit_motion_console.png`.

## Gesture and state proof

The edited Showcase project was loaded once in its Sentinel process.

- All 13 scalar rails were exercised through the strict viewport-control drag
  route. Representative exact readbacks:
  - Master Rate `0.825 -> 2.275`; wide head `0.2574 -> 0.7525`.
  - Lane speed `1.037501 -> 3.012499`; head `0.2727 -> 0.7532`.
  - Amplitude `0.25 -> 0.75`; head `0.2727 -> 0.7532`.
  - Shape `0.75 -> 2.25`; head `0.25294 -> 0.75`.
- Motion Bias wrote exact targets `[0.23, 0.71]` and `[0.77, 0.29]`; the
  923 x 213 reticles landed at `[0.2308, 0.6725]` and
  `[0.77345, 0.32466]`, within 0.038 normalized units.
- Mute toggled `false -> true -> false`; the local panel changed 29.97%.
- Burst remained a momentary parameter but produced 384 accent pixels and a
  21.99% local pixel change while held.
- At 207 x 154, Master Rate still wrote `0.825 -> 2.275` and its head moved
  `0.28889 -> 0.75556`.
- `content_size == render_size` at both 923 x 213 and 207 x 154, a 4.46x width
  change.

### Control-verdict rubric

Every surviving Canvas control passed the 5A rubric: it is a coupled
performance gesture whose drawn state is attached to the live waveform
instrument, while exact numeric setup remains available in Properties.

| Controls | Verdict | Evidence |
| --- | --- | --- |
| `master_rate` | keep | global motion gesture; exact value and rail head proved at both extents |
| `lfo1_speed`, `lfo2_speed`, `lfo3_speed`, `lfo4_speed` | keep | per-lane temporal gestures attached to the four live traces |
| `lfo1_amp`, `lfo2_amp`, `lfo3_amp`, `lfo4_amp` | keep | per-lane spatial-energy gestures attached to trace amplitude |
| `lfo1_shape`, `lfo2_shape`, `lfo3_shape`, `lfo4_shape` | keep | compact waveform-mode gestures with exact state retained in Properties |
| `motion_bias` | keep | asymmetric two-axis performance gesture with reticle proof |
| `mute` | keep | immediate performance state with parameter and local accent proof |
| `burst` | keep | momentary performance action with held-state pixel proof |

All 13 scalar controls were individually exercised at 0.25 and 0.75. Each
bound value landed at its expected range-mapped target, every detected rail
head was within 0.05 normalized units, and every pair moved by more than 0.1.

### Scene Group bind liveness

Each of the eight Fruit group controls was driven from its group path, observed
at the target module parameter, and restored exactly in the still-loaded
Gallery:

| Group control | Drive -> observed module | Restored |
| --- | --- | --- |
| Motion World | `1 -> 0 -> 0` | `1 / 1` |
| Swarm Clones | `2 -> 1 -> 1` | `2 / 2` |
| Fruit Scale | `0.58 -> 0.6495 -> 0.6495` | `0.58 / 0.58` |
| Lifecycle Rate | `0.08 -> 0.222 -> 0.222` | `0.08 / 0.08` |
| Interval Enabled | `true -> false -> false` | `true / true` |
| Capture Slot | `-1 -> 0 -> 0` | `-1 / -1` |
| Card Tool | `0 -> 1 -> 1` | `0 / 0` |
| Camera View | `2 -> 0 -> 0` | `2 / 2` |

## Pixel probes

The final 923 x 213 capture is `wide_final_923x213.png` in the phase capture
folder and the curated copy is `proof/fruit_motion_console.png`.

- Exact ink `(234,236,230)`: 2,328 pixels.
- Exact rule `(57,59,56)`: 2,209 pixels, including 2,209 one-pixel vertical
  runs and horizontal runs up to 215 pixels.
- Exact warm accent `(255,112,28)`: 54 pixels, including the shell origin at
  `(19,19)`; the brighter control accent `(245,112,36)` contributed 133
  pixels.
- Connected high-luma glyph components measured 21, 15, and 7 pixels high,
  proving three distinct typography tiers.

## Presets

The Gallery importer had intentionally omitted the standalone Scene Group
presets. Three gallery-local whole-group presets were restored:

- `Live Fill`
- `Frozen Gallery`
- `Performance`

Each captures 167 pipeline parameters across eight pipelines, all eight exposed
group parameters, and all eight bypass flags. Host-owned `camera_ref` and four
StreamDiff engine-selection fields were explicitly excluded after Sentinel
rejected them as non-presettable.

Every recall applied 183 values with exact group readback:

- Live Fill -> Frozen Gallery changed 68.5273% of 1280 x 720 pixels.
- Frozen Gallery -> Performance changed 86.4222%.
- Performance remained healthy at 1280 x 720 with frames advancing.

Both project-scoped node presets also remain valid:

- `Four Lane Flight`: 16 applied, zero skipped, 10.5835% panel change.
- `Transit Chamber`: 14 parameters plus durable state applied, zero skipped,
  67.6071% Program change.

The first in-place save was denied because suspended `label_gen` had not
allocated its durable state buffer. Cycling through the seven already-loaded
groups once initialized their state without reloading the project; the retry
succeeded.

## Health, profile, and guards

- `module-ui.ps1 validate`: `OK Fruit Motion Console (16 controls)`.
- Compile status: 2/2 passes, `ok`, zero lints.
- Fruit LFO wide-session median wall time:
  `0.74425 ms -> 0.5872 ms` (**-21.1%**).
- `Fruit_LFO`, `Fruit_Scene`, `Fruit_Group_Output`, and the Gallery switcher
  remained healthy and cooking.
- Proof bundle contains graph, links, profile, pipeline health, expressions,
  and output. Full-window capture returned
  `No window found matching 'Sentinel'` and remains operator-unproven.
- Official-example validator: 51 active modules, zero orphan, zero errors.
  Fifty-one generated `.sentinel` shader-cache directories were removed before
  the clean rerun; they are regenerable.
- Public-promotion report-only run: `mode=dry-run`, 220 expected changes,
  `pushed=false`, zero validation findings. Nothing was promoted.

## Pending

- Phase 5G final Showcase Gallery resync and curated proof refresh.
- Human taste approval and operator-only full-window screenshot proof.
