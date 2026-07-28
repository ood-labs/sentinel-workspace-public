# Phase 5G — Showcase Gallery Resync

## Scope

Completed the final Phase 5 collection review after 5B–5F landed. The Gallery
was launched in a fresh interactive Sentinel process and
`showcase_gallery.sentinel` was loaded exactly once. The initial harness request
timed out while the 35 MB project was still hydrating; the load was not
reissued, and the existing process became responsive normally.

No later phase and no public promotion was started.

## Copy-set and compile proof

The five bundled sui3 headers have identical normalized hashes across
Topographic, Strata, Desert, Living Room, and Showcase Gallery.

Every imported panel module matches its source authority file-for-file:

- `signal`: four files across source, workspace original, and Gallery.
- `strata_control`: four files across source, workspace original, and Gallery.
- `dada_control`: four files across source, workspace original, and Gallery.
- `LR_Furnishings`: ten files across source and Gallery.
- `LR_Lighting`: four files across source and Gallery.
- `LR_Architecture`: six files across source and Gallery.

Gallery compile checks:

| Panel | Passes | Parameters | Lints |
| --- | ---: | ---: | ---: |
| `signal` | 2 | 18 | 0 |
| `strata_control` | 2 | 13 | 0 |
| `dada_control` | 2 | 12 | 0 |
| `LR_Furnishings` | 8 | 20 | 0 |
| `LR_Lighting` | 2 | 4 | 0 |
| `LR_Architecture` | 3 | 16 | 0 |
| `Fruit_LFO` | 2 | 16 | 0 |

`module-ui.ps1 validate` passed all seven panels with control counts
2 / 4 / 4 / 6 / 4 / 0 / 16.

## Gallery-context gesture proof

`tools/example-ui-guards.py` now registers the six imported panels as Gallery
targets in addition to `Fruit_LFO`.

Representative strict viewport gestures ran inside the loaded Gallery:

- Topographic `manual_energy`: `0.25 -> 0.75`, heads
  `0.25389 -> 0.75130`.
- Strata `marble_mix`: `0.5 -> 1.5`, heads
  `0.25389 -> 0.75130`.
- Desert `warp_primary`: `0.3 -> 0.9`, heads
  `0.25389 -> 0.75130`.
- Living Room Lighting `daylight`: `0.75 -> 2.25`, heads
  `0.25532 -> 0.74894`.
- Furnishings Snap: `true -> false -> true`, 430 -> 0 -> 430 accent
  pixels, 27.69% local change.
- Fruit re-proved all 13 sliders, Mute, and Motion Bias. Master Rate wrote
  `0.825 -> 2.275`; Motion Bias wrote `[0.23,0.71]` and `[0.77,0.29]`
  with reticle error below 0.038; Mute round-tripped with a 29.97% panel
  change.

The momentary Burst host latch was serialized as `1` by the prior in-place
save despite StateTree returning zero. The project value is corrected to `0`
so the next Gallery load starts inactive; this is the documented button-latch
hazard, not a shader workaround.

## Same-extent panel review

`proof/panel_collection.png` contains all seven Gallery panel captures at
923 x 213. Every panel reported:

- compiled and healthy with frames advancing;
- `effective_mode=canvas`, `resolution_mode=follow_panel`;
- nonzero `content_size == render_size == [923,213]`.

Pixel measurements:

| Panel | Exact rule color | 1 px runs | 2 px runs | Glyph component heights | Warm accent / lit |
| --- | --- | ---: | ---: | --- | ---: |
| Topographic | `(57,59,56)` | 1,820 | 0 | 7 / 15 / 21 | 2.028% |
| Strata | `(61,62,60)` | 2,261 | 0 | 7 / 15 / 21 | 2.132% |
| Desert | `(61,62,60)` | 2,262 | 0 | 7 / 15 / 21 | 3.485% |
| Furnishings | `(61,62,60)` | 1,259 | 0 | 7 / 18 / 21 | 8.214% |
| Lighting | `(57,59,56)` | 140 | 0 | 7 / 10 / 15 / 21 | 0.151% |
| Architecture | `(77,78,75)` | 721 | 0 | 10 / 15 / 18 / 21 | 2.881% |
| Fruit | `(71,73,70)` | 2,211 | 0 | 7 / 15 / 21 | 1.254% |

Tier 1 aesthetic verdict: at one dock extent the collection reads as a single
scientific-instrument family—black fields, white and gray geometry, thin
rules, bitmap type, and sparse orange live-state accents—while each surface
retains a distinct information hierarchy. Human taste approval remains
pending.

## Switching and solo proof

All seven `select/<slug>` actions triggered and resolved to the expected group:

`annotation_87` through `annotation_93` for Living Room, Face, Fruit,
Topographic, Strata, Desert, and Industrial respectively.

Each group output and the Groups-mode Mux stayed healthy at 1280 x 720.
Adjacent switch captures changed:

`98.7204%, 99.9960%, 99.9945%, 92.7151%, 37.4952%, 98.7038%`.

With Topographic selected and `solo_upstream=true`, a 2.5 second window gave:

- `Gallery_Scene_Switcher`: +67 frames.
- `Topo_Group_Output`: +67 frames.
- non-selected `SD_Face`: +0.
- non-selected `Fruit_SD`: +0.

The 0.75 second Industrial-to-Topographic crossfade was sampled at
0.0168 / 0.4634 / 0.9183 seconds. Mean RGB distance from the start progressed
7.2258 -> 42.4948 -> 46.2897, while the mid sample remained 8.2626 from the
settled end. The Mux was healthy and selected `annotation_90` afterward.
`proof/runtime-switching.json` carries the machine-readable refresh.

## Proof and guards

- Gallery proof bundle regenerated with graph, links, profile, health,
  expressions, and output. The host-owned window screenshot again returned
  `No window found matching 'Sentinel'` and remains operator-unproven.
- Guard self-test rejected every deliberately broken bundle, module-copy,
  slider-head, pad-reticle, and toggle-accent variant.
- `test-official-examples.ps1`: all eight fixture assertions passed.
- Final validator:
  - Topographic: 15 active, 0 orphan, 0 errors.
  - Strata: 10 active, 0 orphan, 0 errors.
  - Desert: 6 active, 0 orphan, 0 errors.
  - Living Room: 6 active, 0 orphan, 0 errors.
  - Gallery: 51 active, 0 orphan, 0 errors.
- The final compile sweep regenerated 51 Gallery `.sentinel` shader caches;
  exactly those verified caches were removed before the clean validator.
- All-project promotion report-only run:
  `mode=dry-run`, 414 expected changes, `pushed=false`, zero validation
  findings. Nothing was promoted.

## Pending

- Phase-level `$audit` and final `$end-session`.
- Human taste approval and operator-only full-window screenshot proof.
