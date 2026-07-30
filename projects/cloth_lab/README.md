# Cloth Lab

Cloth Lab is a bundled example of a real-time XPBD cloth engine, driven by kick
detection. Load `cloth_lab.sentinel`, double-click `cloth_engine` to use its
viewport, and play some music.

It is also the reference for two things beyond cloth: the **single-dispatch
groupshared solver** pattern, and **audio-driven physics via a monotonic counter**.

| Node | Type | Role |
| --- | --- | --- |
| `cloth_engine` | `module` | The whole simulation: interaction, solver, metrics, render. Internal camera. |
| `cloth_audio` | `audio` | Audio In, default loopback. Publishes `Spectrum`. |
| `cloth_bands` | `module` (`audio_bands`) | Kick / snare / hat detection. Its Canvas panel is the tuning surface. |

`cloth_audio -> cloth_bands` is a real data link. **`cloth_bands -> cloth_engine`
is an expression, not a wire**, so there is nothing to follow in the graph — see
the `AUDIO DRIVE` annotation. The binding is:

```
cloth_engine/parameters/kick_count_in  =  ref("cloth_bands/control_outputs/kick_count")
```

## Using it

| Input | Action |
| --- | --- |
| Left drag on the cloth | Grab a patch and pull it |
| `G` / `X` | Grab tool / Cut tool |
| `Z` / `V`, or Alt+wheel | Brush smaller / larger |
| `R` | Reset the sheet |
| RMB + WASD | Fly the camera |

Plain wheel belongs to the camera on purpose. Grab acquires on a real left-button
press, so flying with RMB never grabs.

The `Kick Strike Membrane` project preset restores the packaged look. Presets here
carry the full ~98 KB of durable cloth state, so recalling one restores the exact
configuration of the sheet, not just the sliders.

## How the strike works

Every kick fires **one velocity impulse at a random interior vertex**, and the taut
sheet rings outward on its own. There is no ripple simulation — the solver is the
wave equation.

Three decisions worth copying:

- **Drive off the monotonic counter, not the envelope.** `kick_count` gives an
  unambiguous edge with no threshold of your own to tune, and cannot re-fire while
  an envelope decays. A counter jump of 30,000 (which happens when you swap
  drivers) fires exactly one strike, not a burst.
- **An impulse, not a force.** A velocity change is frame-rate independent by
  construction. Modules cook far above display rate, so a force would need
  `_DeltaTime` scaling and would still smear across cooks.
- **The strike point is inset three cells from the border**, so it never lands on a
  pinned corner and get swallowed.

`interact` runs before `solve` in the manifest, so `strikeArmed` can be set for
exactly one cook and consumed the same cook — same-cook producer to consumer is the
only pass handoff direction the module system orders explicitly.

## Controls that matter

**Solver.** `Substeps` x `Sweeps` is the quality budget. Many substeps with few
sweeps beats the reverse. `Bend` is deliberately low (0.08 default): above ~0.3 it
irons the sheet into a rigid plane.

**Letting it stretch.** Three separate ceilings, in order of impact:

1. `Attach Slack` — the real cap. Long-range attachment forbids exceeding the rest
   distance from an anchor by more than this, and no amount of soft `Stretch` can
   override it. Set `Long-Range Attach` to 0 to remove the cap entirely.
2. `Stretch` — 0.0 is a rubber band, 1.0 is inextensible fabric.
3. `Tear Strain` — at low values the fabric rips before it can stretch anywhere
   interesting, so raise it (or disable tearing) for extreme stretch.

**`Slack / Tension`** (`rest_scale`) changes what the cloth *wants* to be rather
than how hard it insists. Above 1 there is more material than the frame, so it goes
slack and folds; below 1 it pulls itself drum-taut. Note that tension below 1 puts
the sheet in permanent standing tension of exactly `1/tension - 1`, so with tearing
enabled raise `Tear Strain` above that figure first.

**Strike.** `Strike Force`, `Strike Radius`, and `Damping` — lower damping rings
longer, which is most of the feel.

## Measured behaviour

All settled from reset, on an RTX PRO 6000:

| Scene | Peak tensile strain |
| --- | --- |
| Banner in wind, top edge pinned | 2.5% |
| Sphere drape | 0.78% |
| Free fall | 0.012% |

`min_clearance` reads exactly `cloth_thickness` on a sphere drape — zero
penetration. Cost is **0.56 ms GPU** for 16 substeps x 3 sweeps x 12
barrier-separated constraint colours, plus a 110k-vertex render pass.

Control outputs (`mean_strain`, `max_strain`, `mean_speed`, `max_speed`, `kinetic`,
`torn_edges`, `min_clearance`) are the diagnostic surface. Every real defect found
while building this was located by toggling one thing and re-reading a number;
none were diagnosable from the render.

## Reusable pieces

The engine is built on three shared headers, bundled here under `modules/_shared/`:

- `xpbd/xpbd.hlsli` — distance and sign-aware curvature constraints, long-range
  attachment, collider projections, friction, compliance mapping. Includes the
  grid graph-colouring table and the compliance calibration table.
- `surface/bicubic.hlsli` — Catmull-Rom patch with analytic tangents, for
  simulate-coarse / render-fine surfaces.
- `viewport/pick3d.hlsli` — camera ray from pointer, nearest-along-ray pick key,
  and the event-handling rules.

Engineering notes and the traps behind them: `knowledge/gpu-cloth-and-xpbd.md`.
Audio wiring: `knowledge/audio-reactivity.md`.

Regenerate runtime evidence on demand with
`sentinel_capture action=proof_bundle pipeline_id=cloth_engine`; captures are
machine-local and are not part of the public project.

## Component map

| Component | Type | Receives | Publishes or contributes |
| --- | --- | --- | --- |
| `cloth_audio` | Audio In | Windows default loopback endpoint | PCM, Spectrum, Mel Bands, level, and peak |
| `cloth_bands` | Module | `cloth_audio` Spectrum data | band histories, kick/snare/hat envelopes, counts, peaks, thresholds, and levels |
| `cloth_engine` | Module | band-driven expressions plus viewport/camera input | XPBD simulation, cloth records, metrics, and final rendered texture |

The `cloth_engine` preview is the reviewed output. Audio In requires no engine
pack. Study chronological Spectrum consumption and simulation ownership; build
new detectors and material behavior for the user's audio rather than importing
this cloth as a stock effect.
