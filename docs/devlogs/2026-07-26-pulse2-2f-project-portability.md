---
type: devlog
date: 2026-07-26
phase: 2
subphase: 2F
status: complete
approval: pending
summary: "Bundled projects/pulse2/, README with the fft_size trap and data contract, D9 engine asks; all four portability criteria pass"
---

## Done

`projects/pulse2/` saved with `bundle_modules`, allowlisted in `.gitignore`, and
proven to load and score from the bundle rather than from `modules/`.

All four pass criteria met:

1. **Bundled `compile_check` succeeds.** `projects/pulse2/modules/pulse2_console`
   compiles standalone (13 params, 4 passes), as does the bundled
   `pulse2_analyzer` (43 params, 13 passes) — proving the `_shared` includes
   resolve from inside the bundle.
2. **Clean load, relative paths, all nodes healthy.** All four modules save with
   relative `project_dir` values (`modules/pulse2_analyzer` etc.),
   `unresolved_project_dirs` is empty, and all five nodes report healthy after a
   `load_project` with `confirm`.
3. **Regions reload byte-identically.** Snapshot before and after the clean load:
   every one of the 12 `rgn*` parameters identical, and in fact every authored
   parameter identical. The only two that differ are `project_dir` (now the
   bundled path, which is the point of the test) and `gate_level` (expression-
   driven live value).
4. **Committed table reproduces from the clean load.** `score_detector.py
   --baseline scores/2E2.json` run against the bundle-loaded graph: **+0.000 on
   every lane of every pattern**, regression gate PASS.

`bundle_modules` does not follow shared include directories, so
`modules/_shared/{ui,au_hud,fonts,anim,pulse2}` were copied in manually — the
bundled `_shared/pulse2/regions.hlsli` is byte-identical to the source.

The `gate_level` expression (`ref("pulse2_audio/control_outputs/level")`)
survives save and load on both `pulse2_analyzer` and `pulse_baseline`. That
matters more than it looks: it drives the signal gate, and without it the
detector reports confident nonsense on silence.

### Documentation

- `projects/pulse2/README.md` — build requirement (`audio` type, absent at or
  below 0.5.48), graph roles, the **`fft_size` coverage trap**, the `Hits` data
  contract including the per-lane serial rule, measured F1, and the known
  continuity limitation stated plainly.
- `docs/engine-asks-audio-in.md` (D9) — six engine asks ranked by measured
  evidence, each naming what it would fix. The two highest are phase-preserving
  spectral data (with `hats_only_150` named as provably unrescuable without it)
  and publishing Spectrum coverage metadata (cheapest high-value item).

Proof bundle written to `projects/pulse2/proof/` — graph, links, health,
expressions, output capture, window screenshot. It stays gitignored under the
repo's standing `projects/*/proof/` rule.

## Issues

None in 2F. Phase 2's outstanding item is 2E2 criterion 3 (beat continuity),
which is recorded in that sub-phase's devlog and stated as a known limitation in
the project README rather than left implicit.

## Next

Phase 2 complete pending approval. Beat continuity is the open thread — the
`beat_snap` mechanism is in place and disabled, with the measured lead recorded.
