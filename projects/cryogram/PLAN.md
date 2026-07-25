# CRYOGRAM

**An instrument that grows a crystal, measures it, and draws the measurement — until the drawing starts seeding the crystal.**

---

## 1. The concept

A closed observational loop in three declared layers, each visible as its own region of the graph:

| Layer | Question | Nodes |
| --- | --- | --- |
| **SPECIMEN** | What is actually there | anisotropic crystal growth field |
| **MEASUREMENT** | What the machine believes is there | analysis proxy → real `features` node → tracker → lattice planner |
| **INTERPRETATION** | What the machine draws from that belief | strata renderer, filament renderer, compositor, grade |

The avant-garde move is the **fourth edge**: INTERPRETATION feeds back into SPECIMEN. Confidently-tracked grains and high-tension lattice filaments become nucleation seeds in the crucible. The instrument's own measurement changes what it is measuring. Nothing in the loop is decorative — every node exists because the layer above it needs a belief the layer below cannot supply.

## 2. Source semantics

No camera or video is available and diagnostic test imagery is forbidden, so the first semantic node is an **authored generator**: a real anisotropic solidification model (continuous-fraction cellular growth with orientation inheritance, faceted by an n-fold anisotropy kernel, annealed by grain age). This is not a test pattern — it is the specimen the whole piece is about, and it produces genuinely detectable structure:

- **grains** → blobs
- **triple junctions / facet vertices** → corners
- **grain boundaries + orientation hatching** → lines

That is why `features` is meaningful here rather than ornamental: the specimen was designed to be measurable.

## 3. Data-to-visual mapping contract

| Detected | Meaning | Drawn as |
| --- | --- | --- |
| Blob centroid + area | a grain | tracked identity, ID label, age ring |
| Blob persistence across frames | grain survived | warm accent saturation (identity = warmth) |
| Blob centroid velocity | growth drift | strata flow direction |
| Corner cluster | facet vertex | lattice node |
| Corner proximity graph | crystal connectivity | filament under tension |
| Filament length vs. rest length | stress | stroke weight + brightness |
| Line angle histogram | dominant orientation | strata contour rotation |

## 4. Palette and motion language

Black field. White and gray geometry. Crisp thin strokes, measurement overlays, registration marks, Scientifica type. **One warm accent (amber), reserved exclusively for records the instrument has confidently and continuously tracked.** Untracked/new/dying records stay gray. Warmth therefore *means* identity — it is a readout, not decoration.

Motion is instrument motion: shared `_shared/anim` springs and staggers, phase integration, no hand-rolled easing, no drifting glow.

## 5. Interaction contract

Every authored control must beat an ordinary Properties slider:

- **Probe placement** — click the console stage to place measurement probes that locally bias nucleation. Spatial, so Properties cannot express it.
- **Anneal brush** — drag to melt regions back to liquid. Spatial and continuous.
- **Filament tension gate** — an XY pad that gates which lattice edges survive by (length, confidence). Two coupled thresholds; a pad reads them together in a way two sliders do not.
- **Direct grain selection** — pick a tracked grain, promote it, watch it survive the anneal.

Exact numeric shaping (rates, thresholds, hatch pitch, grade) stays in Properties.

## 6. Build order — one semantic node at a time

Each node: author → compile_check → create → place → link → poll compile → inspect health/frames/schemas → focus + open_window → exercise controls → capture → fix any weak preview before moving on.

**Phase A — SPECIMEN**
1. `cryo_crucible` — anisotropic solidification generator (1280x720)

**Phase B — MEASUREMENT**
2. `cryo_proxy` — 480x270 analysis proxy with its own legible preview
3. `features` — real Features node, one task enabled at a time, profiled before/after
4. `cryo_grain_tracker` — persistent IDs, hysteresis, velocity, age; `Grains` data out + control outs
5. `cryo_lattice` — bounded proximity graph over corners with max degree + hysteresis; `Filaments` data out

**Phase C — INTERPRETATION**
6. `cryo_strata` — topographic strata driven by grain field and dominant line angle
7. `cryo_filament` — tensioned lattice draw
8. `cryo_comp` — layer compositor

**Phase D — INTERFACE**
9. `cryo_console` — `panel: canvas / follow_panel` authored instrument console: fitted Program stage, probe placement, anneal brush, tension pad, live telemetry; publishes `Probes` data out
10. Scene Groups + 4–8 curated exposed controls, each tested in the open Properties panel

**Phase E — EXPLORATION LOOP** *(explicit, repeating)*
> Repeat until the exit test passes:
> 1. Name one thing the piece cannot currently say.
> 2. Author exactly one new module that says it.
> 3. Wire, prove, capture, and evaluate against the direction.
> 4. **Keep, revise, or delete.** Deleting is a valid and expected outcome.
>
> **Exit test:** two consecutive rounds produce nothing that survives step 4, *and* a vision evaluation of the composited output scores the piece as legible, intentional, and non-generic.

**Phase F — CLOSURE**
11. `cryo_seedback` — interpretation → specimen feedback edge (the conceptual payload)

**Phase G — POLISH**
12. `cryo_grade` — film grade, registration marks, halation, vignette
13. Choreography pass (conductor cues / staggered entrances)
14. Final control-surface audit, proof bundle, checkpoint, save

## 7. Proof criteria

- Every node: `stats.healthy=true`, frames climbing, non-blank non-generic preview inspected in the real UI.
- Every data producer: `capture_data_port` shows real varying records AND the node's own preview decodes them legibly.
- Features: profiled before/after each task enable; reverted immediately on wall-time regression.
- Coordinate discipline: any scaled pass derives extents via `GetDimensions`, never from root `_Resolution`.
- Interaction: every gesture exercised through real viewport input, with before/after captures.
- Final: `proof_bundle` + `checkpoint` + saved `.sentinel` with bundled modules.
