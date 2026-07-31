# Prism Reliquary

A dark-studio product shot rebuilt from a reference image: an iridescent fur torus on a
glossy black floor, with a smoked-glass double cross, a lattice of cut chips, chrome and
marbled spheres, a white light ring, and a soap membrane draped across the left of frame.

Everything is ray-marched signed-distance geometry lit by one authored HDR studio. There is
no diffusion, no photographic source, and no bitmap asset in the project.

Reviewed output: **`PR_Post`** (output `Program`), 1080 x 1350.

**Study this one for filmic rendering** — thin-film refraction, depth-of-field with real
bokeh, HDR bloom, and the antialiasing strategy that makes all three hold together.

---

## Component map

```
PR_Plan ──Cast──> PR_Env ──Studio(tex)──┐
   │                                     ├─> PR_Render ──Beauty──> PR_Post ─> Program
   └──────────────Cast───────────────────┘
```

| Node | Single responsibility |
| --- | --- |
| `PR_Plan` | **Plan authority and editor.** Decides where every element sits. Publishes one 96-record `Cast` buffer, a schematic preview, and the show clock. Click-select, drag-move, keyboard edits. |
| `PR_Env` | The studio as a lat-long HDR panorama — key softbox, two rim strips, broken horizon band, cyclorama. |
| `PR_Render` | SDF ray-marcher, internal camera. Passes: `solids` (opaque, one reflection bounce) and `film` (the transmissive membrane). Publishes **RGBA16F with linear depth in alpha**. |
| `PR_Post` | Lens and film finish: gather-bokeh defocus, bloom, cross flare, aberration, vignette, grade, ACES, grain, edge AA. |

---

## The data contract

One record type, one buffer, one `role` discriminator — `_shared/relic.hlsli`.

```
CastRec = pos float3 · radius float · rot float4 · dims float3 · role float
        · tint float3 · mat float · p0 · p1 · seed · active
        · flags float · aux float3                                (96 bytes)
```

The reference is a **hybrid**: organic masses next to a technical chip family next to a
graphic glyph. Rather than run two contracts, every family is a `CastRec` and `role` says
how to read `dims`, `p0`, `p1`.

**Fixed slot ranges**, so the marcher never scans 96 records: `0` stage · `1` fur torus ·
`2–11` glyph bars · `12` chip plate · `16–55` chips (**addressed by cell**, so a sample
point inverts to one indexed read instead of a 40-record scan) · `56–59` spheres · `60`
ring · `61` membrane · `62–63` posts · `95` editor header.

`flags` carries `F_EDITED` / `F_FLOOR`. **Selection is deliberately not a flag** — it lives
only in the editor header, so it cannot be stored twice and fall out of sync.

---

## The frame contract

Layout is authored in **reference-image coordinates** and projected to world by
`pr_place()`; `pr_unplace()` is the exact inverse and is what the schematic draws with, so
plan and render cannot drift. This works only because the camera pose is part of the
composition: position `(0, 2.22, 12.0)`, FOV 28°. The long lens reproduces the reference's
flat perspective.

The pose is saved as the **`Frame Contract`** node preset on `PR_Render`. Recall it after
flying the camera.

---

## Filmic rendering notes

**Thin-film refraction.** The membrane uses a real interference model (`pr_thinfilm`) — an
optical path difference through a film of a given thickness at a given incidence, sampled at
three wavelengths, with the π reflection phase shift. Bands therefore compress toward
grazing angles and shift with thickness, which is what separates a soap membrane from
tinted glass. The thickness field is fbm-driven and drifts with the clock, so the bands
crawl across the folds.

**Depth of field.** Gather bokeh with golden-angle spiral sampling (uniform disc density, no
ring artefacts, no frame-to-frame crawl), a scatter-as-gather reach test so sharp foreground
does not halo onto blurred background, and highlight weighting so bright speculars round
into discs. Runs **before** bloom — bloom is glare produced *by* the lens.

**Iridescence on the pelt.** Spectral phase driven by the **minor angle** around the tube,
so bands run concentric with the hole. Gated on a highlight (`envSpec` off the analytic
normal), never on irradiance.

**Antialiasing is three separate problems:**

| Symptom | Tool |
| --- | --- |
| Pelt — high-frequency geometric noise | `PR_Render` → Rays Per Axis. Nothing else works. |
| Membrane silhouette — one ray per pixel | Analytic sub-pixel coverage from the march's closest approach (`film.hlsl`). |
| Glyph / chip / ring edges | `PR_Post` edge AA, up to 2 chained passes. |

---

## Traps this build hit

**Handedness flips the whole composition.** Sentinel's camera is left-handed, so a camera at
`+Z` looking toward `-Z` puts world `+X` on the **left**. The first render was a perfect
mirror — convincing enough to look like a layout mistake rather than a projection one.

**`working_format` is not `output_format`.** `working_format` governs intermediate pass
buffers; the texture handed to the *next node* is governed by `output_format`, which
defaults to `RGBA8`. Setting only the former silently clamped alpha to `[0,1]` — and this
module carries **linear depth in alpha**. Every depth collapsed to 1.0, so the defocus
applied uniformly with no depth separation at all, while still looking plausible. It also
clipped the HDR, so bloom ran on `[0,1]` data. This is why `PR_Post` ships a **Diagnostic
View** (`Depth` / `Focus`): a dead depth lane does not error, it just degrades into a
uniform blur.

**A noise-displaced normal against a high-contrast studio gives confetti.** Shading the pelt
from its own displaced normal made every pixel roll an independent reflection direction.
Every broad term is computed from the **analytic normal of the underlying torus**; the noisy
normal supplies only fine strand texture.

**The sheen coefficients have to be tiny.** `envDiffuse` carries the studio's full range
(the key runs at gain 9), so anything near unity turns the pelt into a neon ring.

**An edge filter that reaches too far stops being an edge filter.** The first AA long-filter
walked 1.5× the span with a 0.25 weight floor on rejected samples and softened the entire
frame — the pelt lost its strand detail. Reach is now 0.6× with zero weight on out-of-range
samples, and `AA Edge Search` defaults to 0.

**Chips buried in their own plate.** Offsetting by a fraction of the plate's half-depth puts
them inside the slab, where they render as nothing and look exactly like a broken lookup.

**Recursion is illegal in `cs_5_0`.** Shading cannot call itself to resolve a reflection even
behind a runtime flag. Surface frame first, reflection colour second, `shadeCore` pure.

**Fur is expensive to *compile*, not just to run.** `pr_strand` inlines into the march loop,
the normal (4×) and the AO probe; a third noise octave pushed compilation past five minutes
for no visible gain. Two octaves.

**A persistent buffer outlives its schema.** Reopening a project saved before `CastRec` grew
from 80 to 96 bytes returned the old bytes at the new stride — plausible-looking garbage.
The editor header now carries a role tag and version stamp and rebuilds on mismatch.

**The plan schematic and the render disagree if you fly the camera.** The schematic draws
with the fixed frame contract; the renderer uses the live internal camera. Clicking in the
*render* preview flies the camera (`interactions: [camera]`); the editor is on the *plan*
preview. Recall `Frame Contract` to resync.

---

## Editing the plan

`PR_Plan` is a direct-manipulation editor, not a read-only generator.

| Gesture | Effect |
| --- | --- |
| click | select the element under the pointer (smallest hit wins) |
| drag | move it in the image plane at its own depth |
| `M` | cycle material — per-role list |
| `K` | cycle size step; chips cycle their **cut** instead |
| `X` | toggle on/off (off elements stay selectable) |
| `N` | re-roll that element |
| `R` | reseed the whole layout |
| `C` | clear selection |

Verbs were chosen for *this* subject: the reference is about material and size hierarchy, so
those go on keys. Regeneration is signature-driven and **only structural parameters are in
the signature** — appearance parameters refresh in place so a colour tweak never costs the
user their layout. Derived records follow their parent: dragging the chip plate carries every
chip the user has not hand-placed.

---

## Life

One clock, **integrated from `_DeltaTime`** (never `rate × _Time`, so a speed change never
jumps), living in the plan's persistent header and published on the stage record.

- **Membrane** — three harmonics at incommensurate rates, so it breathes rather than slides
- **Pelt** — the clock is added to the spectral phase; colour creeps, geometry does not move
- **Chrome spheres** — float around a stored rest height; the marble is `F_FLOOR`
- **Lattice** — deliberately discrete: one chip re-cuts every few seconds

All of it skips hand-edited records. Measured: **20.5% of pixels change over 6 s** with the
camera and every parameter fixed. Clip: `proof/motion.mp4`.

---

## Exploration axes

| Axis | Node | Winner | The losers |
| --- | --- | --- | --- |
| `arrangement` | `PR_Plan` | **Reference** | **Orbit** rings satellites round the hero; **Colonnade** stands them in a left register. Both originally threw elements off-frame and were repaired with a frame guard, not deleted. |
| `glyph_style` | `PR_Plan` | **Double Cross** | **Single Cross** is plainer; **Lattice Tower** reads thin because the torus hides two of its four rungs. |
| `fur_style` | `PR_Render` | **Combed** | **Radial** is isotropic noise — moss, not hair; **Frizz** is fur-like but chunkier. |
| `film_form` | `PR_Render` | **Drape** | **Furl** is one broad roll that reads as plastic; **Sheet** is nearly invisible. |

`variation = 0` is exactly the transcribed reference and can never be lost. Sizes are never
re-rolled, so the size hierarchy survives every seed.

---

## Scene Group surface

Eight controls, each verified through the group path: Arrangement, Variation, Seed,
Iridescence, Fur Style, Pelt Bands, Membrane Presence, Exposure. No camera parameter is
exposed — the camera belongs to `PR_Render`'s own Properties.

---

## What was not verified

- **The plan's click / drag / key gestures.** Injected input does not reach Module viewport
  events, so these cannot be machine-proven. Verified instead: the state buffer is declared,
  sized and uploading; bindings publish; signature behaviour; the clock. Material cycling was
  confirmed by hand.
- **Per-node GPU timing.** Detailed Profiling was off, so `profile` reports null `own_ms`.
  Measured: all nodes healthy, 60 FPS, 16.7 ms frame, with 2× supersampling and 8 post passes.
- `proof/window.jpg` from `proof_bundle` renders blank for this window; use
  `sentinel_screenshot action=window` instead.
